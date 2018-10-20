apps = search("aws_opsworks_app","deploy:true")

apps.each do |app|
    Chef::Log.info("Starting deploy for #{app['name']}")

    app_path = "/var/app/#{app['shortname']}"

    directory "#{app_path}" do
        action :create
        owner 'root'
        recursive true
    end

    if app['environment']['LANGUAGE'] == "nodejs"
        Chef::Log.info("NodeJS language detected")


        ports = app['environment']['NODE_PORTS'].split(",")

        current_port = File.read("#{app_path}/current_port");

        if current_port
            ports.delete(current_port)
        end

        port_to_use = ports.sample

        file "#{app_path}/current_port" do
            owner 'root'
            mode "0755"
            content port_to_use
        end

        Chef::Log.info("NodeJS app is using port #{current_port} right now. New deploy will use port #{port_to_use}.")

        template 'nginx-config' do
            source 'nginx.conf.erb'
            path "#{node['nginx']['dir']}/sites-available/#{app['shortname']}"
            action :create
            variables ({ :environment => app['environment'], :domains => app['domains'], :port => port_to_use})
        end

        execute "nxensite #{app['shortname']}" do
          command "/usr/sbin/nxensite #{app['shortname']}"
          not_if do
            ::File.symlink?("#{node['nginx']['dir']}/sites-enabled/#{app['shortname']}") ||
              ::File.symlink?("#{node['nginx']['dir']}/sites-enabled/000-#{app['shortname']}")
          endb
        end

        app['enviroment']['NODE_PORT'] = port_to_use

    else
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

        unless app['environment']['NO_GEARMAN']
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
        end

        supervisorEnvironmentVars = {}

        app['environment'].each do |k,v|
            supervisorEnvironmentVars[k] = v.gsub("%","%%")
        end

        web_app "#{app['shortname']}" do
          server_name app['domains'].first
          server_aliases app['domains'].drop(1)
          docroot "#{app_path}/current#{app['attributes']['document_root']}"
          template "webapp.conf.erb"
          environment app['environment']
        end

        template 'nginx-config' do
            source 'nginx.conf.erb'
            path "#{node['nginx']['dir']}/sites-available/#{app['shortname']}"
            action :create
            variables ({ :environment => app['environment'], :domains => app['domains'], :port => 8080})
        end

        execute "nxensite #{app['shortname']}" do
          command "/usr/sbin/nxensite #{app['shortname']}"
          not_if do
            ::File.symlink?("#{node['nginx']['dir']}/sites-enabled/#{app['shortname']}") ||
              ::File.symlink?("#{node['nginx']['dir']}/sites-enabled/000-#{app['shortname']}")
          endb
        end

        execute "a2enmod php7.2" do
            ignore_failure true
            user "root"
        end
    end

    unless app['environment']['NO_GEARMAN']
        include_recipe "gearman::default"
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
        restart_command "touch /var"
        before_migrate do
            Chef::Log.info("Installing composer")
            current_release = release_path

            execute "composer install --prefer-dist --optimize-autoloader  --no-interaction --no-progress" do
                only_if {::File.exists?("#{current_release}/composer.json")}
                live_stream true
                action :run
                user "root"
                cwd "#{current_release}"
            end

            execute "npm install --production" do
                only_if {::File.exists?("#{current_release}/package.json")}
                live_stream true
                action :run
                user "root"
                cwd "#{current_release}"
            end

            unless app['environment']['NO_GEARMAN']
                supervisor_service "gearman" do
                    action [:enable, :restart]
                    process_name "gearman"
                    command "gearmand --queue-type=mysql --mysql-host=#{app['environment']['DATABASE_SERVER_ADDRESS']} --mysql-port=3306 --mysql-user=#{app['environment']['DATABASE_USER']} --mysql-password=#{app['environment']['DATABASE_PASSWORD']} --mysql-db=gearman --mysql-table=gearman_queue"
                    autostart true
                    autorestart true
                    numprocs 1
                    user "root"
                    redirect_stderr true
                    stdout_events_enabled true
                    stderr_events_enabled true
                end

                supervisor_service "gearman_process" do
                    action [:enable, :restart]
                    process_name "gearman-worker-%(process_num)s"
                    command "php #{current_release}/api/gearman/worker.php"
                    autostart true
                    autorestart true
                    numprocs 10
                    environment supervisorEnvironmentVars
                    user "root"
                    redirect_stderr true
                    stdout_events_enabled true
                    stderr_events_enabled true
                end
            end

            if app['environment']['LANGUAGE'] == "nodejs"
                template 'node-env-file' do
                    source 'node.envfile.erb'
                    path "#{current_release}/.env"
                    action :create
                    variables ({ :environment => app['environment'] })
                end

                execute "pm2 start app.js -i max -n app-#{port_to_use}" do
                    ignore_failure false
                    action :run
                    user "root"
                    cwd "#{current_release}"
                end

                execute "service nginx start | nginx -s reload" do
                    ignore_failure false
                    user "root"
                end

                execute "pm2 stop app-#{current_port}" do
                    ignore_failure false
                    action :run
                    user "root"
                end
            else
                execute "a2dismod mpm_event | service apache2 start | service apache2 graceful" do
                    ignore_failure false
                    user "root"
                end

                execute "service nginx start | nginx -s reload" do
                    ignore_failure false
                    user "root"
                end
            end

        end

        after_restart do
            Chef::Log.info("Finished app install")
        end
    end
end