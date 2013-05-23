#
# Cookbook Name:: storm
# Recipe:: default
#
# Copyright 2012, Webtrends, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe "java"

if ENV["deploy_build"] == "true" then
  log "The deploy_build value is true so un-deploy first"
  include_recipe "storm::undeploy-default"
end

# install repo-based dependency packages
%w{unzip python}.each do |pkg|
  package pkg do
    action :install
  end
end

# install cookbook_file-based dependency packages
cookbook_file "zeromq_2.1.7-1_amd64.deb" do
  path "/tmp/zeromq_2.1.7-1_amd64.deb"
  owner "root"
  group "root"
  mode "0444"
  action :create_if_missing
end

dpkg_package "zeromq" do
  source "/tmp/zeromq_2.1.7-1_amd64.deb"
  action :install
end

cookbook_file "jzmq_2.1.0-1_amd64.deb" do
  path "/tmp/jzmq_2.1.0-1_amd64.deb"
  owner "root"
  group "root"
  mode "0444"
  action :create_if_missing
end

dpkg_package "jzmq" do
  source "/tmp/jzmq_2.1.0-1_amd64.deb"
  action :install
end

# find the Nimbus node.  optionally use cluster_role to allow for multiple clusters in the same environment
if node['storm']['cluster_role']
  nimbus_server = search(:node, "roles:#{node['storm']['nimbus']['role']} AND roles:#{node['storm']['cluster_role']} AND chef_environment:#{node.chef_environment}").first
else
  nimbus_server = search(:node, "roles:#{node['storm']['nimbus']['role']} AND chef_environment:#{node.chef_environment}").first
end


# search for zookeeper servers
zookeeper_quorum = Array.new
  search(:node, "roles:#{node['storm']['zookeeper']['role']} AND chef_environment:#{node.chef_environment}").each do |n|
  zookeeper_quorum << n['fqdn']
end

install_dir = "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"

# setup storm group
group "storm"

# setup storm user
user "storm" do
  comment "Storm user"
  gid "storm"
  shell "/bin/bash"
  home "/home/storm"
  supports :manage_home => true
end

# setup directories
%w{install_dir local_dir log_dir}.each do |name|
  directory node['storm'][name] do
    owner "storm"
    group "storm"
    action :create
    recursive true
  end
end

# download storm
remote_file "#{Chef::Config[:file_cache_path]}/storm-#{node[:storm][:version]}.zip" do
  source "#{node['storm']['release_url']}/storm-#{node['storm']['version']}.zip"
  owner  "storm"
  group  "storm"
  mode   00744
  not_if "test -f #{Chef::Config[:file_cache_path]}/storm-#{node['storm']['version']}.zip"
end

# uncompress the application zip file into the install directory
execute "unzip" do
  user    "storm"
  group   "storm"
  creates "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"
  cwd     "#{node['storm']['install_dir']}"
  command "unzip #{Chef::Config[:file_cache_path]}/storm-#{node['storm']['version']}.zip"
end

# create a link from the specific version to a generic current folder
link "#{node['storm']['install_dir']}/current" do
	to "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"
end

# storm.yaml
template "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}/conf/storm.yaml" do
  source "storm.yaml.erb"
  mode 00644
  variables(
    :nimbus_server => nimbus_server['fqdn'],
    :zookeeper_quorum => zookeeper_quorum
  )
end

# sets up storm users profile
template "/home/storm/.profile" do
  owner  "storm"
  group  "storm"
  source "profile.erb"
  mode   00644
  only_if "test -f /home/storm"
  variables(
    :storm_dir => "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"
  )
end

template "#{install_dir}/bin/killstorm" do
  source  "killstorm.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :log_dir => node['storm']['log_dir']
  })
end
