include_recipe "phpapp::setup_php5"

app = search(:aws_opsworks_app).first

app_path = "/var/app/#{app['shortname']}"

deploy "#{app_path}" do
    action :rollback
end