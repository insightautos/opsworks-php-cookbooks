node.default['apache']['listen'] = ['*:8080']
node.default['apache']['version'] = '2.4'
node.default['apache']['package'] = 'apache2'
node.default['php']['packages'] = ['libapache2-mod-php7.2', 'libapache2-mod-php','php7.2-dev', 'php7.2-common', 'php7.2-cli', 'php7.2-soap', 'php7.2-xml', 'php7.2-xmlrpc', 'php7.2-mysqlnd','php7.2-pgsql', 'php7.2-opcache', 'php7.2-pdo', 'php7.2-imap', 'php7.2-mbstring', 'php7.2-intl', 'php7.2-gd','php7.2','php-pear','php7.2-curl']

node.default['php']['version'] =  '7.2.17'
node.default['php']['fpm_package'] = 'php7.2-fpm'
node.default['php']['fpm_pooldir'] = '/etc/php/7.2/fpm/pool.d'
node.default['php']['fpm_service'] = 'php7.2-fpm'
node.default['php']['fpm_socket'] = '/var/run/php/php7.2-fpm.sock'
node.default['php']['fpm_default_conf'] = '/etc/php/7.2/fpm/pool.d/www.conf'

node.default['php']['mysql'] = 'php7.2-mysqlnd'
node.default['php']['pgsql'] = 'php7.2-pgsql'
node.default['php']['curl'] = 'php7.2-curl'
node.default['php']['ext_conf_dir'] = '/etc/php/7.2/mods-available'

node.default['php']['conf_dir'] = "/etc/php/7.2"
# add the EPEL repo
#yum_repository 'epel' do
#    description 'Extra Packages for Enterprise Linux'
#    mirrorlist 'http://mirrors.fedoraproject.org/mirrorlist?repo=epel-7&arch=x86_64'
#    gpgkey 'http://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7'
#    action :create
#end

# add the webtatic repo
#yum_repository 'webtatic' do
#    description 'webtatic Project'
#    mirrorlist 'http://repo.webtatic.com/yum/el7/x86_64/mirrorlist'
#    gpgkey 'http://repo.webtatic.com/yum/RPM-GPG-KEY-webtatic-el7'
#    action :create
#end

total_ram = case node['os']
when /.*bsd/
  node.memory.total.to_i / 1024 / 1024
when 'linux'
  node.memory.total[/\d*/].to_i / 1024
when 'darwin'
  node.memory.total[/\d*/].to_i
when 'windows', 'solaris', 'hpux', 'aix'
  node.memory.total[/\d*/].to_i / 1024
end

apache_process_size = 5
fpm_process_size = 5

s = shell_out("nproc --all")
cpu_cores = s.stdout.to_i

node.default['apache']['event']['serverlimit'] = (total_ram*0.85).round
node.default['apache']['event']['startservers'] = cpu_cores
node.default['apache']['event']['minsparethreads'] =  25
node.default['apache']['event']['maxsparethreads'] = 75
node.default['apache']['event']['threadlimit'] = 64
node.default['apache']['event']['threadsperchild'] = 25
node.default['apache']['event']['maxrequestworkers'] = ((total_ram*0.85)/apache_process_size).round
node.default['apache']['event']['maxconnectionsperchild'] = 5000

node.default['apache']['prefork']['maxconnectionsperchild'] = 2500
node.default['apache']['prefork']['maxrequestworkers'] = 1500
node.default['apache']['prefork']['minspareservers'] =  25
node.default['apache']['prefork']['maxspareservers'] = 75
node.default['apache']['prefork']['serverlimit'] = 64

execute "LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php" do
    ignore_failure false
    user "root"
end
execute "apt-get update" do
    ignore_failure false
    user "root"
end

bash 'disable_php7.2' do
  interpreter "bash"
  user 'root'
  code <<-EOH
    if hash a2dismod 2>/dev/null; then
        a2dismod php7.2
        a2dismod php7.3
        a2dismod php7.4
        a2dismod php8.0
        a2dismod mpm_event
    fi
    EOH
end

include_recipe "build-essential"
include_recipe "apache2::default"
include_recipe "apache2::mod_rewrite"
include_recipe "apache2::mod_access_compat"
include_recipe "apache2::mod_proxy"
include_recipe "apache2::mod_proxy_http"
include_recipe "apache2::mpm_event"
include_recipe "php"

execute "apt-get remove -y --purge php7.3*" do
    ignore_failure false
    user "root"
end

execute "apt-get remove -y --purge php7.4*" do
    ignore_failure false
    user "root"
end

execute "apt-get remove -y --purge php8.0*" do
    ignore_failure false
    user "root"
end

addconfig = {:max_requests => 5000}

php_fpm_pool 'default' do
  action :install
  max_children ((total_ram*0.85)/fpm_process_size).round
  start_servers cpu_cores*4
  min_spare_servers cpu_cores*2
  max_spare_servers cpu_cores*4
end

execute "a2enmod php7.2" do
    ignore_failure true
    user "root"
end

template 'apache2-prefork' do
    source 'mpm_prefork.conf.erb'
    path "/etc/apache2/conf-available/dealr_mpm_prefork.conf"
    action :create
    variables ({ :node => node })
end

execute "a2enconf dealr_mpm_prefork" do
    ignore_failure true
    user "root"
end