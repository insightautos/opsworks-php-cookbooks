include_recipe "build-essential"
include_recipe "phpapp::setup_php72"
include_recipe "yum"
include_recipe "phpapp::setup_ghostscript"
include_recipe "phpapp::php_mcrypt_enable"
include_recipe "imagemagick::devel"
include_recipe "imagemagick"
include_recipe 'apt::default'
include_recipe 'openresty::default'
include_recipe 'openresty::luarocks'
node.default['python']['install_method'] = 'source'
#node.default['python']['prefix_dir'] = '/usr/local'
package "python-pip"
#node.default['poise-python']['install_python2'] = true
#include_recipe 'poise-python::default'

bash 'pip_link' do
  interpreter "bash"
  user 'root'
  code <<-EOH
        #!/bin/sh

        rm -f /usr/bin/pip
        ln -s /usr/local/bin/pip /usr/bin/pip

    EOH
end

node.default['nodejs']['install_method'] = 'binary'
include_recipe "nodejs"
include_recipe "gearman::default"
include_recipe "supervisor::default"

node.default['nginx']['port'] = 80
#node.default['nginx']['conf_template'] = 'nginx_main.conf.erb'
node.default['nginx']['worker_shutdown_timeout'] = 10
node.default['nginx']['pid'] = '/run/nginx.pid'
node.default['nginx']['default_site_enabled'] = false

file "/etc/apt/apt.conf" do
    owner 'root'
    mode "0755"
    content 'DPkg::options { "--force-confnew"; };'
end

include_recipe "nginx::default"
resources('template[nginx.conf]').cookbook 'phpapp'

node.default['apt']['unattended_upgrades']['enable'] = true
node.default['apt']['unattended_upgrades']['allowed_origins'] = ["${distro_id}:${distro_codename}-security"]

include_recipe "apt::unattended-upgrades"

package "git"
#package "python-setuptools"
package "ntp"
package "ntpdate"

bash 'install_composer' do
  interpreter "bash"
  user 'root'
  code <<-EOH
        #!/bin/sh

        EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

        if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]
        then
            >&2 echo 'ERROR: Invalid installer signature'
            rm composer-setup.php
            exit 1
        fi

        php composer-setup.php --quiet
        RESULT=$?
        mv composer.phar /usr/local/bin/composer
        rm composer-setup.php
        exit $RESULT
    EOH
end

package "libzip-dev"
package "gearman-tools"
package "gearman"
package "libmysqlclient-dev"

#npm_package 'pm2'

execute "npm config set prefix /usr/local && npm install -g pm2" do
    ignore_failure false
    user "root"
end

#execute "curl -sL https://sentry.io/get-cli/ | bash" do
#    ignore_failure false
#    user "root"
#end

bash 'install_extensions' do
  interpreter "bash"
  user 'root'
  code <<-EOH
    #pecl config-set php_ini /etc/php/7.2/apache2/php.ini

    #pear config-set php_ini /etc/php/7.2/apache2/php.ini

    v8installed="$(pecl list | grep -i v8js)"

    if [ -z "$v8installed" ]
    then
        printf "/opt/v8\n" | pecl install v8js-2.1.0
    fi

    imagickinstalled="$(pecl list | grep -i imagick)"

    if [ -z "$imagickinstalled" ]
    then
        printf "\n" | pecl install imagick
   fi

    zipinstalled="$(pecl list | grep -i zip)"

    if [ -z "$zipinstalled" ]
    then
        printf "\n" | pecl install zip
    fi

    echo "extension=v8js.so" | tee /etc/php/7.2/mods-available/v8js.ini
    echo "extension=imagick.so" | tee /etc/php/7.2/mods-available/imagick.ini
    echo "extension=zip.so" | tee /etc/php/7.2/mods-available/zip.ini

    echo "extension=v8js.so" | tee /etc/php/7.2/cli/conf.d/20-v8js.ini
    echo "extension=imagick.so" | tee /etc/php/7.2/cli/conf.d/20-imagick.ini
    echo "extension=zip.so" | tee /etc/php/7.2/cli/conf.d/20-zip.ini

    phpenmod -v ALL -s ALL v8js
    phpenmod -v ALL -s ALL imagick
    phpenmod -v ALL -s ALL zip
    phpenmod -v ALL -s ALL pdo_pgsql

    EOH
end

bash 'install_extensions' do
  interpreter "bash"
  user 'root'
  only_if {node['nginx_amplify']['api_key'] != ''}
  code <<-EOH
    cd /tmp/
    curl -L -O https://github.com/nginxinc/nginx-amplify-agent/raw/master/packages/install.sh
    API_KEY="#{node['nginx_amplify']['api_key']}" sh ./install.sh

    EOH
end

bash 'install_gearman' do
  interpreter "bash"
  user 'root'
  code <<-EOH

    extensiondir=$(php-config --extension-dir)

    gearmaninstalled="$(ls $extensiondir | grep -i gearman)"

    if [ -z "$gearmaninstalled" ]
    then
        cd /tmp/
        wget https://github.com/wcgallego/pecl-gearman/archive/gearman-2.0.5.zip
        unzip gearman-2.0.5.zip
        cd pecl-gearman-gearman-2.0.5
        phpize
        ./configure
        make
        make install
    fi

    echo "extension=gearman.so" | tee /etc/php/7.2/mods-available/gearman.ini
    phpenmod -v ALL -s ALL gearman

    EOH
end

bash 'install_sass' do
  interpreter "bash"
  user 'root'
  code <<-EOH

    extensiondir=$(php-config --extension-dir)

    sassinstalled="$(ls $extensiondir | grep -i sass)"

    if [ -z "$sassinstalled" ]
    then
        echo "install"
        cd /tmp/
        rm -rf sassphp
        git clone git://github.com/forrestmid/sassphp
        cd sassphp
        git submodule init
        git submodule update
        cd lib && make -C libsass -j5 && cd ..
        phpize
        ./configure
        make
        make install
    fi

    echo "extension=sass.so" | tee /etc/php/7.2/mods-available/sass.ini
    phpenmod -v ALL -s ALL sass

    EOH
end

#execute "printf \"/opt/v8\n\" | pecl install v8js" do
#    ignore_failure false
#    user "root"
#end

#execute "printf \"\n\" | pecl install imagick" do
#    ignore_failure false
#    user "root"
#end

execute "service ntp restart" do
    ignore_failure true
end

# install supervisord
execute "easy_install supervisor"

# disable opcache fast shutdown
execute "sed -i 's/opcache.fast_shutdown=1/opcache.fast_shutdown=0/g' /etc/php/7.2/php.ini" do
    ignore_failure true
end

bash 'disable_php7.3' do
  interpreter "bash"
  user 'root'
  code <<-EOH
    if hash a2dismod 2>/dev/null; then
        a2dismod php7.3
        a2dismod php7.4
        a2enmod php7.2
    fi
    EOH
end

execute "composer global require hirak/prestissimo" do
    ignore_failure true
end

mysql_client 'default' do
  action :create
end

package "luarocks"

openresty_luarock 'lua-resty-auto-ssl' do
  action :install
end
#openresty_luarock 'luasql-mysql' do
#  action :install
#end

execute "luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mysql" do
    ignore_failure true
end

bash 'setup-lua-ssl' do
  interpreter "bash"
  user 'root'
  ignore_failure true
  code <<-EOH
    mkdir /etc/resty-auto-ssl
    chown www-data /etc/resty-auto-ssl
    EOH
end
bash 'setup-default-ssl' do
  interpreter "bash"
  user 'root'
  code <<-EOH
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
       -subj '/CN=sni-support-required-for-valid-ssl' \
       -keyout /etc/ssl/resty-auto-ssl-fallback.key \
       -out /etc/ssl/resty-auto-ssl-fallback.crt
    EOH
end

include_recipe "phpapp::setup_php72"