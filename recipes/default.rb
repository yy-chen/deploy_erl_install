#
# Cookbook Name:: erl_deploy_install
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
# Author:: Seth Chisamore <schisamo@opscode.com>

APP_NAME = data_bag_item("application", "deploy")["app"]
AREA_NAME = data_bag_item("application", "deploy")["name"]
VERSION = data_bag_item("application", "deploy")['version']
APP_CONFIG = data_bag_item("application", "deploy")["app_config"]
VMARGS = data_bag_item("application", "deploy")["vmargs"]
if APP_CONFIG != "" and VMARGS != ""
    APP_CONFIG = APP_CONFIG.split("\n")
    VMARGS = VMARGS.split("\n")
end
WORK_DIR = "/home/dhcd/release"
area_path = "#{WORK_DIR}/#{AREA_NAME}"

#创建定时任务，当原定时任务存在时在脚本运行完时调用
cron "create crontab" do
    minute '*/1'
    user 'dhcd'
    command <<-EOH
    /home/dhcd/release/monitor/monitor.sh
    EOH
    action :nothing
end

#当应用已存在时删除定时任务，然后调用停止应用任务
cron "change crontab" do
    minute '*/1'
    user 'dhcd'
    command <<-EOH
    /home/dhcd/release/monitor/monitor.sh
    EOH
    action :delete
    only_if{File.exists?("#{area_path}")}
    notifies :run, 'execute[stop app]', :immediate
    notifies :create, 'cron[create crontab]', :delayed
end

#如应用已经存在，停止原应用 删除crontab定时任务
execute "stop app" do
    command <<-EOH
    cd #{area_path}/bin && ./#{APP_NAME} stop
    EOH
    returns [0,1]
    timeout 40
    only_if{File.exists?("#{area_path}")}
end

#保存原有配置文件
if File.exists?("#{area_path}") and APP_CONFIG == "" and VMARGS == ""
    if File.exists?("/tmp/etc")
        ruby_block "rename tmp etc" do
            block do
                FileUtils.mv("/tmp/etc", "/tmp/etc_back")
            end
        end
    end

    ruby_block "save etc config" do
        block do
            FileUtils.cp_r("#{area_path}/etc", "/tmp/etc")
        end
    end
end

#如果原应用路径存在， 备份日志
if File.exists?("#area_path")
    if File.exists?("/tmp/log")
        ruby_block "rename tmp log" do
            block do
                FileUtils.mv("/tmp/log", "/tmp/log_back")
            end
        end
    end
    ruby_block "save log" do
        block do
            FileUtils.cp_r("#{area_path}/log", "/tmp/log")
        end
    end
end

directory "#{area_path}" do
    action :delete
    recursive true
    only_if{File.exists?("#{area_path}")}
end

#如果工作目录不存在，创建工作目录
directory "#{WORK_DIR}" do
    action :create
    recursive true
    only_if{!File.exists?("#{WORK_DIR}")}
end

#将放在tmp目录下的应用文件拷贝来并且重命名
ruby_block "cp app" do
    block do
        FileUtils.cp_r("/tmp/#{APP_NAME}_#{VERSION}", "#{area_path}")
    end
end

#如果tmp路径下有备份的日志文件则删除当前日志文件，拷贝备份日志来
directory "#{area_path}/log" do
    action :delete
    recursive true
    only_if(File.exists?("/tmp/log"))
end

if File.exists?("/tmp/log")
    ruby_block "cp log" do
        block do
            FileUtils.mv("/tmp/log", "#{area_path}/log")
        end
    end
end

directory "/tmp/log" do
    action :delete
    recursive true
    only_if{File.exists?("/tmp/log")}
end

#删除默认配置文件
file "#{area_path}/etc/#{APP_NAME}.config" do
    action :delete
    only_if{File.exists?("#{area_path}/etc/#{APP_NAME}.config")}
end

file "#{area_path}/etc/vm.args" do
    action :delete
    only_if{File.exists?("#{area_path}/etc/vm.args")}
end

if APP_CONFIG != "" and VMARGS != ""
    #根据template以及databag中存储的信息生成新配置文件
    template "#{area_path}/etc/#{APP_NAME}.config" do
        source "app.config.erb"
        variables(:directives=>APP_CONFIG)
    end

    template "#{area_path}/etc/vm.args" do
        source "vm.args.erb"
        variables(:directives=>VMARGS)
    end
else 
    directory "#{area_path}/etc" do
        action :delete
        recursive true
    end
    ruby_block "copy old config" do
        block do
            FileUtils.mv("/tmp/etc", "#{area_path}/etc")  #如果不存在会崩
            #对应页面上没有填配置，这台机器也没有这个区的情况
        end
    end
end

#启动应用
execute "start app" do
    command <<-EOH
        cd #{area_path}/bin
        ./#{APP_NAME} start
        sleep 5
        ./#{APP_NAME} ping  #等待5秒后ping此应用检查是否启动
    EOH
    returns [0]
end

directory "/tmp/#{APP_NAME}_#{VERSION}" do
    action :delete
    recursive true
end

#更新node属性
flag = 0
for i in 0..(node.normal[APP_NAME].length-1)
    instance = node.normal[APP_NAME][i]
    if(instance['name'] == AREA_NAME)
        flag = 1
        node.normal[APP_NAME][i]['version'] = VERSION
    end
end
if flag == 0
    ins = Hash.new
    ins['name'] = AREA_NAME
    ins['version'] = VERSION
    if node.normal[APP_NAME].empty?
        node.normal[APP_NAME] = Array.new
    end
    node.normal[APP_NAME] << ins
end
