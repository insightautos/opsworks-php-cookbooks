include_recipe "build-essential"
include_recipe "apache2::default"
include_recipe "apache2::mod_rewrite"
include_recipe "apache2::mod_access_compat"
include_recipe "apache2::mod_proxy"
include_recipe "apache2::mod_proxy_http"
#include_recipe "apache2::mod_php"
include_recipe "yum"
include_recipe "phpapp::setup_php5"
include_recipe "phpapp::setup_ghostscript"
include_recipe "phpapp::php_mcrypt_enable"
include_recipe "imagemagick::devel"
include_recipe "imagemagick"
#include_recipe "phpapp::setup_v8"
include_recipe 'apt'
include_recipe "nodejs"

php_pear_channel 'pear.php.net' do
  action :update
end

php_pear_channel 'pecl.php.net' do
  action :update
end

php_pear 'imagick' do
  action :install
end

package "git"
package "python-setuptools"
package "ntp"
package "ntpdate"
package "php56-gd"

#php_pear 'v8js' do
#  version "0.6.4"
#  action :install
#end

execute "service ntpd restart" do
    ignore_failure true
end

execute "chkconfig ntpd on" do
    ignore_failure true
end

# install supervisord
execute "easy_install supervisor"

# disable opcache fast shutdown
execute "sed -i 's/opcache.fast_shutdown=1/opcache.fast_shutdown=0/g' /etc/php-5.6.ini" do
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
