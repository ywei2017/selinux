#
# Cookbook:: selinux
# Resource:: state
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

include ::SELinux::Cookbook::StateHelpers

default_action :nothing

property :config_file, String,
          default: '/etc/selinux/config'

property :persistent, [true, false],
          default: true,
          description: 'Persist status update to the selinux configuration file'

property :policy, String,
          default: lazy { default_policy_platform },
          equal_to: %w(default minimum mls src strict targeted),
          description: 'SELinux policy type'

property :automatic_reboot, [true, false, Symbol],
          default: false,
          description: 'Perform an automatic node reboot if required for state change'

deprecated_property_alias 'temporary', 'persistent', 'The temporary property was renamed persistent in the 4.0 release of this cookbook. Please update your cookbooks to use the new property name.'

action_class do
  include ::SELinux::Cookbook::StateHelpers

  def render_selinux_template(action)
    Chef::Log.warn(
      'It is advised to set the configuration first to permissive to relabel the filesystem prior to enforcing.'
    ) if selinux_disabled? && action == :enforcing

    unless new_resource.automatic_reboot
      Chef::Log.warn('Changes from disabled require a reboot.') if selinux_disabled? && %i(enforcing permissive).include?(action)
      Chef::Log.warn('Disabling selinux requires a reboot.') if (selinux_enforcing? || selinux_permissive?) && action == :disabled
    end

    template "#{action} selinux config" do
      path new_resource.config_file
      source 'selinux.erb'
      cookbook 'selinux'
      variables(
        selinux: action.to_s,
        selinuxtype: new_resource.policy
      )
    end
  end

  def node_selinux_restart
    unless new_resource.automatic_reboot
      Chef::Log.warn("SELinux state change to #{action} requires a manual reboot as SELinux is currently #{selinux_state} and automatic reboots are disabled.")
      return
    end

    outer_action = action
    reboot 'selinux_state_change' do
      delay_mins 1
      reason "SELinux state change to #{outer_action} from #{selinux_state}"

      action new_resource.automatic_reboot.is_a?(Symbol) ? new_resource.automatic_reboot : :reboot_now
    end
  end
end

action :enforcing do
  execute 'selinux-setenforce-enforcing' do
    command '/usr/sbin/setenforce 1'
  end unless selinux_disabled? || selinux_enforcing?

  execute 'debian-selinux-activate' do
    command selinux_activate_cmd
  end if selinux_activate_required?

  render_selinux_template(action) if new_resource.persistent
  node_selinux_restart if state_change_reboot_required?
end

action :permissive do
  execute 'selinux-setenforce-permissive' do
    command '/usr/sbin/setenforce 0'
  end unless selinux_disabled? || selinux_permissive?

  execute 'debian-selinux-activate' do
    command selinux_activate_cmd
  end if selinux_activate_required?

  render_selinux_template(action) if new_resource.persistent
  node_selinux_restart if state_change_reboot_required?
end

action :disabled do
  raise 'A non-persistent change to the disabled SELinux status is not possible.' unless new_resource.persistent

  render_selinux_template(action)
  node_selinux_restart if state_change_reboot_required?
end
