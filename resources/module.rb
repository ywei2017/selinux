#
# Cookbook:: selinux
# Resource:: module
#
# Copyright:: 2016-2024, Chef Software, Inc.
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

unified_mode true

property :module_name, String,
          name_property: true,
          description: 'Override the module name'

property :source, String,
          description: 'Module source file name'

property :content, String,
          description: 'Module source as String'

property :cookbook, String,
          default: lazy { cookbook_name },
          description: 'Cookbook to source from module source file from'

property :base_dir, String,
          default: '/etc/selinux/local',
          description: 'Directory to create module source file in'

action_class do
  def selinux_module_filepath(type)
    path = ::File.join(new_resource.base_dir, "#{new_resource.module_name}")
    path.concat(".#{type}") if type
  end

  def list_installed_modules
    shell_out!('semodule --list-modules').stdout.split("\n").map { |x| x.split(/\s/).first }
  end
end

action :create do
  directory new_resource.base_dir

  if property_is_set?(:content)
    file selinux_module_filepath('te') do
      content new_resource.content

      mode '0600'
      owner 'root'
      group 'root'

      action :create

      notifies :run, "execute[Compiling SELinux modules at '#{new_resource.base_dir}']", :immediately
    end
  else
    cookbook_file selinux_module_filepath('te') do
      cookbook new_resource.cookbook
      source new_resource.source

      mode '0600'
      owner 'root'
      group 'root'

      action :create

      notifies :run, "execute[Compiling SELinux modules at '#{new_resource.base_dir}']", :immediately
    end
  end

  execute "Compiling SELinux modules at '#{new_resource.base_dir}'" do
    cwd new_resource.base_dir
    command "make -C #{new_resource.base_dir} -f /usr/share/selinux/devel/Makefile"
    timeout 120
    user 'root'

    action :nothing

    notifies :run, "execute[Install SELinux module '#{selinux_module_filepath('pp')}']", :immediately
  end

  raise "Compilation must have failed, no 'pp' file found at: '#{selinux_module_filepath('pp')}'" unless ::File.exist?(selinux_module_filepath('pp'))

  execute "Install SELinux module '#{selinux_module_filepath('pp')}'" do
    command "semodule --install '#{selinux_module_filepath('pp')}'"
    action :nothing
  end
end

action :delete do
  %w(fc if pp te).each do |type|
    next unless ::File.exist?(selinux_module_filepath(type))

    file selinux_module_filepath(type) do
      action :delete
    end
  end
end

action :install do
  raise "Module must be compiled before it can be installed, no 'pp' file found at: '#{selinux_module_filepath('pp')}'" unless ::File.exist?(selinux_module_filepath('pp'))

  unless list_installed_modules.include? new_resource.module_name
    converge_by "Install SELinux module #{selinux_module_filepath('pp')}" do
      shell_out!("semodule --install '#{selinux_module_filepath('pp')}'")
    end
  end
end

action :remove do
  if list_installed_modules.include? new_resource.module_name
    converge_by "Remove SELinux module #{new_resource.module_name}" do
      shell_out!("semodule --remove '#{new_resource.module_name}'")
    end
  end
end
