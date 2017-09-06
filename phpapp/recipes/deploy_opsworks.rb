include_recipe "phpapp::setup_php5"

app = search(:aws_opsworks_app).first

app_path = "/var/app/#{app['shortname']}"

web_app "#{app['name']}" do
  server_name "manage.dealr.cloud"
  server_aliases ["demo.dealr.cloud"]
  docroot "#{app_path}/current"
  template "webapp.conf.erb"
  environment app['environment']
end

directory "#{app_path}" do
    action :create
    owner 'root'
    recursive true
end

file "#{app_path}/git_key" do
    owner 'root'
    mode "0600"
    content app['app_source']['ssh_key']
end
file "#{app_path}/git_key.sh" do
    owner 'root'
    mode "0755"
    content "#!/bin/sh\nexec /usr/bin/ssh -o 'StrictHostKeyChecking=no' -i #{app_path}/git_key \"$@\""
end

deploy "#{app_path}" do
    repository app['app_source']['url']
    revision app['app_source']['revision']
    ssh_wrapper "#{app_path}/git_key.sh"

    symlink_before_migrate.clear
    create_dirs_before_symlink.clear
    purge_before_symlink.clear
    symlinks.clear
    before_migrate do
        Chef::Log.info("Installing composer")
        current_release = release_path
        execute "composer install --prefer-dist --optimize-autoloader  --no-interaction --no-progress" do
            live_stream true
            action :run
            user "root"
            cwd "#{current_release}"
        end

        service "httpd" do
          action :restart
        end
    end

    after_restart do
        Chef::Log.info("Finishing app install")
    end
end