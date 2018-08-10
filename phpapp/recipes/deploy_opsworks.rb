
app = search(:aws_opsworks_app).first

app_path = "/var/app/#{app['shortname']}"

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
web_app "#{app['name']}" do
  server_name "manage.dealr.cloud"
  server_aliases ["demo.dealr.cloud"]
  docroot "#{app_path}/current"
  template "webapp.conf.erb"
  environment app['environment']
end
execute "a2enmod php7.2" do
    ignore_failure true
    user "root"
end

directory "#{app_path}" do
    action :create
    owner 'root'
    recursive true
end

bash 'install_gearman' do
  interpreter "bash"
  user 'root'
  code <<-EOH

    gearmaninstalled="$(ls /etc/php/7.2/mods-available | grep -i gearman)"

    if [ -z "gearmaninstalled" ]
    then
        cd /tmp/
        wget https://github.com/wcgallego/pecl-gearman/archive/gearman-2.0.5.zip
        unzip gearman-2.0.5.zip
        cd pecl-gearman-master
        phpize
        ./configure
        make
        make install
        echo "extension=gearman.so" | tee /etc/php/7.2/mods-available/gearman.ini
        phpenmod -v ALL -s ALL gearman
    fi

    EOH
end

supervisorEnvironmentVars = {}

app['environment'].each do |k,v|
    supervisorEnvironmentVars[k] = v.gsub("%","%%")
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

include_recipe "gearman::default"

deploy "#{app_path}" do
    repository app['app_source']['url']
    revision app['app_source']['revision']
    ssh_wrapper "#{app_path}/git_key.sh"

    symlink_before_migrate.clear
    create_dirs_before_symlink.clear
    purge_before_symlink.clear
    symlinks.clear
    restart_command "touch /var"
    before_migrate do
        Chef::Log.info("Installing composer")
        current_release = release_path
        execute "composer install --prefer-dist --optimize-autoloader  --no-interaction --no-progress" do
            live_stream true
            action :run
            user "root"
            cwd "#{current_release}"
        end
        execute "npm install" do
            live_stream true
            action :run
            user "root"
            cwd "#{current_release}"
        end

        supervisor_service "gearman" do
            action :disable
        end

        supervisor_service "gearman" do
            action :enable
            process_name "gearman"
            command "gearmand --queue-type=mysql --mysql-host=#{app['environment']['DATABASE_SERVER_ADDRESS']} --mysql-port=3306 --mysql-user=#{app['environment']['DATABASE_USER']} --mysql-password=#{app['environment']['DATABASE_PASSWORD']} --mysql-db=gearman --mysql-table=gearman_queue"
            autostart true
            autorestart true
            numprocs 1
            environment supervisorEnvironmentVars
        end

        supervisor_service "gearman_process" do
            action :disable
        end
        supervisor_service "gearman_process" do
            action :enable
            process_name "gearman-worker-%(process_num)s"
            command "php #{current_release}/api/gearman/worker.php"
            autostart true
            autorestart true
            numprocs 10
            environment supervisorEnvironmentVars
        end
        execute "a2dismod mpm_event | service apache2 restart" do
            ignore_failure false
            user "root"
        end
    end

    after_restart do
        Chef::Log.info("Finished app install")
    end
end