bash 'install_v8' do
  interpreter "bash"
  user 'root'
  code <<-EOH
    wget https://github.com/insightautos/v8js-rpm/releases/download/v8/v8-5.2.371-1.x86_64.rpm
    yum localinstall v8*.rpm -y
    EOH
end