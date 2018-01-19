node.set['apache']['version'] = '2.4'
node.set['apache']['package'] = 'apache2'
node.set['php']['packages'] = ['libapache2-mod-php7.2', 'libapache2-mod-php','php7.2-dev','php7.2-fpm', 'php7.2-common', 'php7.2-cli', 'php7.2-soap', 'php7.2-xml', 'php7.2-xmlrpc', 'php7.2-mysqlnd', 'php7.2-opcache', 'php7.2-pdo', 'php7.2-imap', 'php7.2-mbstring', 'php7.2-intl', 'php7.2-gd','php7.2','php-pear','php7.2-curl']
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
include_recipe "php"


execute "a2enmod php7.2" do
    ignore_failure true
    user "root"
end