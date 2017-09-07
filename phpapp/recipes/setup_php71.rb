node.set['apache']['version'] = '2.4'
node.set['apache']['package'] = 'apache2'
node.set['php']['packages'] = ['libapache2-mod-php7.1', 'libapache2-mod-php','php7.1-dev','php7.1-fpm', 'php7.1-common', 'php7.1-cli', 'php7.1-soap', 'php7.1-xml', 'php7.1-xmlrpc', 'php7.1-mysqlnd', 'php7.1-opcache', 'php7.1-pdo', 'php7.1-imap', 'php7.1-mbstring', 'php7.1-intl', 'php7.1-mcrypt', 'php7.1-gd','php7.1','php-pear','php7.1-curl']
node.set['php']['conf_dir'] = "/etc/php/7.1"
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

execute "add-apt-repository ppa:ondrej/php" do
    ignore_failure false
    user "root"
end
execute "apt-get update" do
    ignore_failure false
    user "root"
end
include_recipe "build-essential"
include_recipe "apache2::default"
include_recipe "apache2::mod_rewrite"
include_recipe "php"