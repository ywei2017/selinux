#
# Cookbook:: selinux
# Resource:: fcontext
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
#

unified_mode true

property :file_spec, String,
          name_property: true,
          description: 'Path to or regex matching the files or directoriesto label'

property :secontext, String,
          required: %i(add modify manage),
          description: 'SELinux context to assign'

property :file_type, String,
          default: 'a',
          equal_to: %w(a f d c b s l p),
          description: 'The type of the file being labeled'

action_class do
  include ::SELinux::Cookbook::StateHelpers

  def current_file_context
    file_hash = {
      'a' => 'all files',
      'f' => 'regular file',
      'd' => 'directory',
      'c' => 'character device',
      'b' => 'block device',
      's' => 'socket',
      'l' => 'symbolic link',
      'p' => 'named pipe',
    }

    contexts = shell_out!('semanage fcontext -l').stdout.split("\n")
    # pull out file label from user:role:type:level context string
    contexts.grep(/^#{Regexp.escape(new_resource.file_spec)}\s+#{file_hash[new_resource.file_type]}/) do |c|
      c.match(/.+ (?<user>.+):(?<role>.+):(?<type>.+):(?<level>.+)$/)[:type]
      # match returns ['foo'] or [], shift converts that to 'foo' or nil
    end.shift
  end

  # Run restorecon to fix label
  # https://github.com/sous-chefs/selinux_policy/pull/72#issuecomment-338718721
  def relabel_files
    spec = new_resource.file_spec
    escaped = Regexp.escape spec

    # find common path between regex and string
    common = if spec == escaped
               spec
             else
               index = spec.size.times { |i| break i if spec[i] != escaped[i] }
               ::File.dirname spec[0...index]
             end

    # if path is not absolute, ignore it and search everything
    common = '/' if common[0] != '/'

    if ::File.exist? common
      shell_out!("find #{common.shellescape} -ignore_readdir_race -regextype posix-egrep -regex #{spec.shellescape} -prune -print0 | xargs -0 restorecon -iRv")
    end
  end
end

action :manage do
  run_action(:add)
  run_action(:modify)
end

action :addormodify do
  Chef::Log.warn('The :addormodify action for selinux_fcontext is deprecated and will be removed in a future release. Use the :manage action instead.')
  run_action(:manage)
end

# Create if doesn't exist, do not touch if fcontext is already registered
action :add do
  if selinux_disabled?
    Chef::Log.warn("Unable to add SELinux fcontext #{new_resource.name} as SELinux is disabled")
    return
  end

  # "add" is performed in two scenarios.
  # 1: The local file_contexts.local has an entry for new_resource.file_spec, but secontext <> new_resource.secontext
  # 2. The local file_contexts.local does NOT have an entry for new_resource.file_spec, AND
  #    either the system default (file_contexts) does not have an entry for new_resource.file_spec, or the secontext <> new_resource.secontext
  # In both scenarios, file_contexts.local is created with a new entry, or the secontext is updated.

  cfc = current_file_context
  unless cfc && cfc == new_resource.secontext
    converge_by "adding label #{new_resource.secontext} to #{new_resource.file_spec}" do
      shell_out!("semanage fcontext -a -f #{new_resource.file_type} -t #{new_resource.secontext} '#{new_resource.file_spec}'")
      relabel_files
    end
  end
end

# Only modify if fcontext exists & doesn't have the correct label already
action :modify do
  if selinux_disabled?
    Chef::Log.warn("Unable to modify SELinux fcontext #{new_resource.name} as SELinux is disabled")
    return
  end

  if current_file_context && current_file_context != new_resource.secontext
    converge_by "modifying label #{new_resource.secontext} to #{new_resource.file_spec}" do
      shell_out!("semanage fcontext -m -f #{new_resource.file_type} -t #{new_resource.secontext} '#{new_resource.file_spec}'")
      relabel_files
    end
  end
end

# Delete if exists
action :delete do
  if selinux_disabled?
    Chef::Log.warn("Unable to delete SELinux fcontext #{new_resource.name} as SELinux is disabled")
    return
  end

  if current_file_context
    converge_by "deleting label for #{new_resource.file_spec}" do
      shell_out!("semanage fcontext -d -f #{new_resource.file_type} '#{new_resource.file_spec}'")
      relabel_files
    end
  end
end
