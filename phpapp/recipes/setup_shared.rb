include_recipe "build-essential"
include_recipe "phpapp::setup_php71"
include_recipe "apache2::default"
include_recipe "apache2::mod_rewrite"
include_recipe "apache2::mod_access_compat"
include_recipe "apache2::mod_proxy"
include_recipe "apache2::mod_proxy_http"
include_recipe "yum"
include_recipe "phpapp::setup_ghostscript"
include_recipe "phpapp::php_mcrypt_enable"
include_recipe "imagemagick::devel"
include_recipe "imagemagick"
include_recipe 'apt'
include_recipe "nodejs"

package "git"
package "python-setuptools"
package "ntp"
package "ntpdate"

bash 'install_extensions' do
  interpreter "bash"
  user 'root'
  code <<-EOH
    pecl config-set php_ini /etc/php/7.1/apache2/php.ini

    pear config-set php_ini /etc/php/7.1/apache2/php.ini

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
execute "sed -i 's/opcache.fast_shutdown=1/opcache.fast_shutdown=0/g' /etc/php/7.1/php.ini" do
    ignore_failure true
end

execute "curl -sS https://getcomposer.org/installer | php" do
    ignore_failure false
end

execute "mv composer.phar /usr/local/bin/composer" do
    ignore_failure false
end

execute "composer global require hirak/prestissimo" do
    ignore_failure true
end
