node.set['apache']['listen'] = ['*:8080']
node.set['apache']['version'] = '2.4'
node.set['apache']['package'] = 'apache2'
node.set['php']['packages'] = ['libapache2-mod-php7.2', 'libapache2-mod-php','php7.2-dev', 'php7.2-common', 'php7.2-cli', 'php7.2-soap', 'php7.2-xml', 'php7.2-xmlrpc', 'php7.2-mysqlnd', 'php7.2-opcache', 'php7.2-pdo', 'php7.2-imap', 'php7.2-mbstring', 'php7.2-intl', 'php7.2-gd','php7.2','php-pear','php7.2-curl']

node.set['php']['fpm_package'] = 'php7.2-fpm'
node.set['php']['fpm_pooldir'] = '/etc/php/7.2/fpm/pool.d'
node.set['php']['fpm_service'] = 'php7.2-fpm'
node.set['php']['fpm_socket'] = '/var/run/php/php7.2-fpm.sock'
node.set['php']['fpm_default_conf'] = '/etc/php/7.2/fpm/pool.d/www.conf'

node.set['php']['mysql'] = 'php7.2-mysqlnd'
node.set['php']['curl'] = 'php7.2-curl'
node.set['php']['ext_conf_dir'] = '/etc/php/7.2/mods-available'

node.set['php']['conf_dir'] = "/etc/php/7.2"
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

apache_process_size = 15
fpm_process_size = 10

s = shell_out("nproc --all")
cpu_cores = s.stdout.to_i

node.set['apache']['event']['serverlimit'] = (total_ram*0.85).round
node.set['apache']['event']['startservers'] = cpu_cores
node.set['apache']['event']['minsparethreads'] =  25
node.set['apache']['event']['maxsparethreads'] = 75
node.set['apache']['event']['threadlimit'] = 64
node.set['apache']['event']['threadsperchild'] = 25
node.set['apache']['event']['maxrequestworkers'] = ((total_ram*0.85)/apache_process_size).round
node.set['apache']['event']['maxconnectionsperchild'] = 1000

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

addconfig = {:max_requests => 1000}

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