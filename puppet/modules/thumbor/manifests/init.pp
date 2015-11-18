# == Class: Thumbor
#
# This Puppet class installs and configures a Thumbor instance
#
# Thumbor is installed as a Python package, and as part of that,
# pip compiles lxml. This is memory-intensive; you might have to
# increase the memory available to the VM with something like
# 'vagrant config vagrant_ram 2048; vagrant reload'.
#
# === Parameters
#
# [*deploy_dir*]
#   Path where Thumbor should be installed (example: '/var/thumbor').
#
# [*cfg_file*]
#   Thumbor configuration file. The file will be generated by Puppet.
#
# [*statsd_port*]
#   Port the statsd instance runs on.
#
# [*sentry_dsn_file*]
#   Path to file containing the sentry dsn file.
#
class thumbor (
    $deploy_dir,
    $cfg_file,
    $statsd_port,
    $sentry_dsn_file,
) {
    require ::virtualenv

    # jpegtran
    require_package('libjpeg-progs')

    # opencv engine
    # activate it with ENGINE='opencv_engine' in thumbor.conf.erb
    # not used here by default because of https://github.com/thumbor/opencv-engine/issues/16
    require_package('python-opencv')

    $statsd_host = 'localhost'
    $statsd_prefix = 'Thumbor'

    virtualenv::environment { $deploy_dir:
        ensure   => present,
        packages => [
            'git+git://github.com/thumbor/thumbor.git',
            'git+git://github.com/gi11es/thumbor-memcached.git',
            'cv2',
            'numpy',
            'opencv-engine',
            'raven',
            'pylibmc', # For memcache original file storage
        ],
        require  => [
            Package['libjpeg-progs'],
            Package['python-opencv'],
        ],
        timeout  => 600, # This venv can be particularly long to download and setup
    }

    # Hack because pip install cv2 inside a virtualenv is broken
    file { "${deploy_dir}/lib/python2.7/site-packages/cv2.so":
        ensure  => present,
        # From python-opencv
        source  => '/usr/lib/python2.7/dist-packages/cv2.so',
        require => Virtualenv::Environment[$deploy_dir],
    }

    file { $cfg_file:
        ensure    => present,
        group     => 'www-data',
        content   => template('thumbor/thumbor.conf.erb'),
        mode      => '0640',
        subscribe => File[$sentry_dsn_file],
    }

    file { '/etc/init/thumbor.conf':
        ensure  => present,
        content => template('thumbor/upstart.erb'),
        mode    => '0444',
    }

    service { 'thumbor':
        ensure    => running,
        enable    => true,
        provider  => 'upstart',
        require   => Virtualenv::Environment[$deploy_dir],
        subscribe => File[$cfg_file, '/etc/init/thumbor.conf'],
    }

    varnish::backend { 'thumbor':
        host   => '127.0.0.1',
        port   => '8888',
        onlyif => 'req.url ~ "^/images/thumb/.*\.(jpeg|jpg|png)"',
    }

    varnish::config { 'thumbor':
        source => 'puppet:///modules/thumbor/varnish.vcl',
        order  => 49, # Needs to be before default for vcl_recv override
    }
}
