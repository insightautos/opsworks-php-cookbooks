node.set['apache']['version'] = '2.4'
node.set['apache']['package'] = 'apache2'

include_recipe "phpapp::setup_shared"

app = search(:aws_opsworks_app).first

# set any php.ini settings needed
template "/etc/php/7.1/apache2/conf.d/app.ini" do
  source "php.conf.erb"
  owner "root"
  group "root"
  mode 0644
end

## set apache2 hosts
#web_app "#{app['name']}" do
#  server_name "manage.dealr.cloud"
#  server_aliases ["demo.dealr.cloud"]
#  docroot "/var/app"
#  template "webapp.conf.erb"
#  environment app['environment']
#end