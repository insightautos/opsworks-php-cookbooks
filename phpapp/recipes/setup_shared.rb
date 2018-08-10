include_recipe "build-essential"
include_recipe "phpapp::setup_php72"
include_recipe "yum"
include_recipe "phpapp::setup_ghostscript"
include_recipe "phpapp::php_mcrypt_enable"
include_recipe "imagemagick::devel"
include_recipe "imagemagick"
include_recipe 'apt::default'
include_recipe "nodejs"
include_recipe "gearman::default"
include_recipe "supervisor::default"

node.set['apt']['unattended_upgrades']['enable'] = true
node.set['apt']['unattended_upgrades']['allowed_origins'] = ["${distro_id}:${distro_codename}-security"]

include_recipe "apt::unattended-upgrades"

package "git"
package "python-setuptools"
package "ntp"
package "ntpdate"
package "composer"
package "libzip-dev"
package "gearman-tools"
package "gearman"
package "libmysqlclient-dev"

bash 'install_extensions' do
  interpreter "bash"
  user 'root'
  code <<-EOH
    pecl config-set php_ini /etc/php/7.2/apache2/php.ini

    pear config-set php_ini /etc/php/7.2/apache2/php.ini

    v8installed="$(pecl list | grep -i v8js)"

    if [ -z "$v8installed" ]
    then
        printf "/opt/v8\n" | pecl install v8js
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

    EOH
end

bash 'install_gearman' do
  interpreter "bash"
  user 'root'
  code <<-EOH

    gearmaninstalled="$(ls /etc/php/7.2/mods-available | grep -i gearman)"

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
        echo "extension=gearman.so" | tee /etc/php/7.2/mods-available/gearman.ini
        phpenmod -v ALL -s ALL gearman
    fi

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

execute "composer global require hirak/prestissimo" do
    ignore_failure true
end
include_recipe "phpapp::setup_php72"