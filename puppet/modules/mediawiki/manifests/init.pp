# == Class: mediawiki
#
# Provision a MediaWiki instance powered by MySQL, served by Apache, and
# customized for development work.
#
# === Parameters

# [*wiki*]
#   Wiki name (default: 'devwiki').
#
# [*admin*]
#   User name for the initial admin account (default: 'admin').
#
# [*pass*]
#   Initial password for admin account (default: 'vagrant').
#
# [*dbname*]
#   Logical MySQL database name.
#
# [*dbuser*]
#   MySQL user to use to connect to the database (default: 'root').
#
# [*dbpass*]
#   Password for MySQL account (default: 'vagrant').
#
# [*server*]
#   Full base URL of host (default: 'http://127.0.0.1:8080').
#
# === Examples
#
#  class { 'mediawiki':
#       wiki  => 'mobiledevwiki',
#       admin => 'mobiledev',
#       pass  => 'secret',
#  }
#
class mediawiki(
	$wiki   = 'devwiki',
	$admin  = 'admin',
	$pass   = 'vagrant',
	$dbname = 'wiki',
	$dbuser = 'root',
	$dbpass = 'vagrant',
	$server = 'http://127.0.0.1:8080',
	$dir    = '/vagrant/mediawiki',
) {
	class { 'php': }
	class { 'phpsh': }
	class { 'mysql':
		dbname   => $dbname,
		password => $pass,
	}

	apache::site { 'default':
		ensure => absent,
	}

	git::clone { 'mediawiki':
		remote    => 'https://gerrit.wikimedia.org/r/p/mediawiki/core.git',
		directory => $dir,
	}


	file { '/etc/apache2/sites-enabled/000-default':
		ensure  => absent,
		require => Package['apache2'],
		before  => Exec['mediawiki setup'],
	}

	# If an auto-generated LocalSettings.php file exists but the database it
	# refers to is missing, assume it is residual of a discarded instance and
	# delete it.
	exec { 'check settings':
		command => "rm ${dir}/LocalSettings.php 2>/dev/null || true",
		require => [ Package['php5'], Git::Clone['mediawiki'], Service['mysql'] ],
		unless  => "php ${dir}/maintenance/eval.php <<<\"wfGetDB(-1)\" &>/dev/null",
		before  => Exec['mediawiki setup'],
	}

	apache::site { 'wiki':
		ensure  => present,
		content => template('mediawiki/mediawiki-apache-site.erb'),
	}

	exec { 'mediawiki setup':
		require     => [ Exec['set mysql password'], Git::Clone['mediawiki'] ],
		creates     => "${dir}/LocalSettings.php",
		cwd         => "${dir}/maintenance/",
		command     => "php install.php ${wiki} ${admin} --pass ${pass} --dbname ${dbname} --dbuser ${dbuser} --dbpass ${dbpass} --server ${server} --scriptpath '/w'",
		notify      => Service['apache2'],
	}


	exec { 'require extra settings':
		require => Exec['mediawiki setup'],
		command => "echo \"require_once( \'/vagrant/LocalSettings.php\' );\" >>${dir}/LocalSettings.php",
		unless  => "grep \"/vagrant/LocalSettings.php\" ${dir}/LocalSettings.php",
	}

	exec { 'set mediawiki install path':
		command => "echo \"export MW_INSTALL_PATH=${dir}\" >> ~vagrant/.profile",
		unless  => 'grep MW_INSTALL_PATH ~vagrant/.profile 2>/dev/null',
	}

	exec { 'set default database':
		command => "echo 'database = \"${dbname}\"' >> /home/vagrant/.my.cnf",
		require => [ Exec['mediawiki setup'], File['/home/vagrant/.my.cnf'] ],
		unless  => "grep 'database = \"${dbname}\"' /home/vagrant/.my.cnf",
	}

	apache::mod { 'alias':
		ensure => present,
	}

	apache::mod { 'rewrite':
		ensure => present,
	}

	file { '/var/www/mediawiki-vagrant.png':
		ensure => file,
		source => 'puppet:///modules/mediawiki/mediawiki-vagrant.png',
	}

	file { '/var/www/favicon.ico':
		ensure  => file,
		require => Package['apache2'],
		source  => 'puppet:///modules/mediawiki/favicon.ico',
	}

	exec { 'configure phpunit':
		creates => '/usr/bin/phpunit',
		command => "${dir}/tests/phpunit/install-phpunit.sh",
		require => Exec['mediawiki setup'],
	}
}
