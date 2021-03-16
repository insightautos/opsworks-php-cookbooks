node.default['apache']['listen'] = ['*:8080']
node.default['nginx']['port'] = 80
#node.default['nginx']['conf_template'] = 'nginx_main.conf.erb'
node.default['nginx']['worker_shutdown_timeout'] = 10
node.default['nginx']['pid'] = '/run/nginx.pid'
node.default['nginx']['default_site_enabled'] = false


apps = search("aws_opsworks_app","deploy:true")
instance = search("aws_opsworks_instance", "self:true").first
require 'chef/mixin/shell_out'
apps.each do |app|

    Chef::Log.info("Starting deploy for #{app['name']}")

    app_path = "/var/app/#{app['shortname']}"

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

    git_command = [
        "sudo ssh-agent bash -c 'ssh-add #{app_path}/git_key &>/dev/null; git ls-remote #{app['app_source']['url']}",
        app['app_source']['revision'] ? " -h #app['app_source']['revision']" : "",
        "' | head -1 | cut -f 1"
      ].compact.join("");
    git_sha = shell_out(git_command).stdout

    app['environment']['GIT_SHA'] = git_sha
    Chef::Log.info("Git Command #{git_command}")
    Chef::Log.info("Git SHA Key #{git_sha}")

    if app['environment']['LANGUAGE'] == "nodejs"
        Chef::Log.info("NodeJS language detected")

        ports = app['environment']['NODE_PORTS'].split(",")

        if File.exist?("#{app_path}/current_port")
            current_port = File.read("#{app_path}/current_port");
            port_to_use = current_port
            # ports.delete(current_port)
        else
            port_to_use = ports.sample
        end


        file "#{app_path}/current_port" do
            owner 'root'
            mode "0755"
            content "#{port_to_use}"
        end

        Chef::Log.info("NodeJS app is using port #{current_port} right now. New deploy will use port #{port_to_use}.")

        template 'nginx-config' do
            source 'nginx-site.conf.erb'
            path "#{node['nginx']['dir']}/sites-available/#{app['shortname']}"
            action :create
            variables ({ :environment => app['environment'], :domains => app['domains'], :port => port_to_use})
        end
        template 'ecosystem.config.js' do
            source 'ecosystem.config.js.erb'
            path "#{app_path}/ecosystem.config.js"
            action :create
            variables ({ :name => app['shortname'], :path => "#{app_path}/current", :errorPath => "#{app_path}/logs/error.log"})
        end

        execute "nxensite #{app['shortname']}" do
          command "/usr/sbin/nxensite #{app['shortname']}"
          not_if {::File.symlink?("#{node['nginx']['dir']}/sites-enabled/#{app['shortname']}") || ::File.symlink?("#{node['nginx']['dir']}/sites-enabled/000-#{app['shortname']}")}
        end

        app['environment']['NODE_PORT'] = port_to_use
    else
        node.default['apache']['listen'].push("*:#{app['environment']['PORT']}")

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
            source 'nginx-site.conf.erb'
            path "#{node['nginx']['dir']}/sites-available/#{app['shortname']}"
            action :create
            variables ({ :environment => app['environment'], :domains => app['domains'], :port => app['environment']['PORT']})
        end
        template "nginx.conf" do
          path "#{node['nginx']['dir']}/nginx.conf"
          source "nginx.conf.erb"
          owner "root"
          group "root"
          mode 00644
          variables ({ :environment => app['environment'], :domains => app['domains'], :port => port_to_use})
          ignore_failure true
        end
        template 'nginx-stub_status-config' do
            source 'nginx.stub_status.conf.erb'
            path "#{node['nginx']['dir']}/conf.d/stub_status.conf"
            action :create
        end

        execute "nxensite #{app['shortname']}" do
          command "/usr/sbin/nxensite #{app['shortname']}"
          not_if {::File.symlink?("#{node['nginx']['dir']}/sites-enabled/#{app['shortname']}") || ::File.symlink?("#{node['nginx']['dir']}/sites-enabled/000-#{app['shortname']}")}
        end

        execute "a2enmod php7.2" do
            ignore_failure true
            user "root"
        end
    end

    unless app['environment']['NO_GEARMAN']
        include_recipe "gearman::default"
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
                only_if {::File.exist?("#{current_release}/composer.json")}
                live_stream true
                action :run
                user "root"
                cwd "#{current_release}"
            end

            execute "npm install --production" do
                only_if {::File.exist?("#{current_release}/package.json")}
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
                    stdout_events_enabled true
                    stderr_events_enabled true
                    redirect_stderr false
                    stderr_logfile "/var/log/supervisor/gearman.log"
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
                    stdout_events_enabled true
                    stderr_events_enabled true
                    redirect_stderr false
                    stderr_logfile "/var/log/supervisor/gearman_process.log"
                end

                supervisor_service "gearman_process_2" do
                    action [:enable, :restart]
                    process_name "gearman-worker-2-%(process_num)s"
                    command "php #{current_release}/api/gearman/worker.php worker-2"
                    autostart true
                    autorestart true
                    numprocs 5
                    environment supervisorEnvironmentVars

                    user "root"
                    stdout_events_enabled true
                    stderr_events_enabled true
                    redirect_stderr false
                    stderr_logfile "/var/log/supervisor/gearman_process_2.log"
                end
            end

            execute "service nginx stop && service nginx start" do
                ignore_failure false
                action :run
                user "root"
                cwd "#{current_release}"
                not_if {::File.exist?("/var/run/nginx.pid")}
            end

            if app['environment']['LANGUAGE'] == "nodejs"
                template 'node-env-file' do
                    source 'node.envfile.erb'
                    path "#{current_release}/.env"
                    action :create
                    variables ({ :environment => app['environment'] })
                end

                execute "pm2 link #{app['environment']['PM2_SECRET_KEY']} #{app['environment']['PM2_PUBLIC_KEY']} #{instance['hostname']}" do
                    ignore_failure false
                    action :run
                    user "root"
                    cwd "#{current_release}"
                    only_if { app['environment']['PM2_PUBLIC_KEY'] != nil && app['environment']['PM2_SECRET_KEY'] != nil }
                end

                execute "service nginx start && nginx -s reload" do
                    ignore_failure false
                    user "root"
                end

                execute "pm2 startOrReload #{app_path}/ecosystem.config.js" do
                    ignore_failure false
                    action :run
                    user "root"
                    cwd "#{app_path}"
                end
            else

                execute "a2dismod mpm_event | service apache2 start | service apache2 graceful" do
                    ignore_failure false
                    user "root"
                end
                bash 'disable_php7.3' do
                  interpreter "bash"
                  user 'root'
                  code <<-EOH
                    if hash a2dismod 2>/dev/null; then
                        a2dismod php7.3
                        a2dismod php7.4
                        a2dismod php8.0
                        a2enmod php7.2
                    fi
                    EOH
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
