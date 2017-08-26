include_recipe "phpapp::setup_php5"

app = search(:aws_opsworks_app).first
app_path = "/var/app"

# set apache2 hosts
web_app "#{app['name']}" do
  server_name "manage.dealr.cloud"
  server_aliases ["demo.dealr.cloud"]
  docroot "/var/app"
  template "webapp.conf.erb"
  environment app['environment']
end

# deploy git repo from opsworks app
application app_path do
  git app_path do
    repository app['app_source']['url']
    deploy_key app['app_source']['ssh_key']
    revision app['app_source']['revision']
  end
end


# install composer
script "install_composer" do
  interpreter "bash"
  user "root"
  cwd "/var/app"
  code <<-EOH
  composer install --prefer-source --optimize-autoloader  --no-interaction
  EOH
end

directory '/var/app' do
  owner 'root'
  group 'root'
  mode '0755'
  action :create
end