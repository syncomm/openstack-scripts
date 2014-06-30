#! /usr/bin/ruby -w

#########################################################################
# Script: openstack-inspect-guests.rb                                   #
# Version: 0.1.0                                                        #
#                                                                       #
# Description:                                                          #
# A script to inspect OpenStack hypervisor instances through libguestfs #
#                                                                       #
# Copyright (C) 2014, Gregory S. Hayes <ghayes@redhat.com>              #
#                                                                       #
# This program is free software; you can redistribute it and/or modify  #
# it under the terms of the GNU General Public License as published by  #
# the Free Software Foundation; either version 2 of the License, or     #
# (at your option) any later version.                                   #
#                                                                       #
# This program is distributed in the hope that it will be useful,       #
# but WITHOUT ANY WARRANTY; without even the implied warranty of        #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
# GNU General Public License for more details.                          #
#                                                                       #
# You should have received a copy of the GNU General Public License     #
# along with this program; if not, write to the                         #
# Free Software Foundation, Inc.,                                       #
# 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             #
#                                                                       #
#########################################################################

require 'guestfs'

class OsCreds 
    # Get credentials from environment
    def initialize()
        @username = ENV['OS_USERNAME']
        @tenant_name = ENV['OS_TENANT_NAME']
        @password = ENV['OS_PASSWORD']
        @auth_url = ENV['OS_AUTH_URL']
        @region_name = ENV['OS_REGION_NAME']
    end
    attr_reader :username, :tenant_name, :password, :auth_url, :region_name
end

def openstack_guest_inspect disk  
  g = Guestfs::Guestfs.new()
  
  # Attach the disk image read-only to libguestfs.
  g.add_drive_opts(disk, :readonly => 1)
  
  # Run the libguestfs back-end.
  g.launch()
  
  # Ask libguestfs to inspect for operating systems.
  roots = g.inspect_os()
  if roots.length == 0
    puts "inspect_vm: no operating systems found"
    exit 1
  end
  
  for root in roots do
    # Mount up the disks, like guestfish -i.
    #
    # Sort keys by length, shortest first, so that we end up
    # mounting the filesystems in the correct order.
    # debug: printf("  Root device:  %s\n", root)
    mps = g.inspect_get_mountpoints(root)
    mps = mps.sort {|a,b| a[0].length <=> b[0].length}
    for mp in mps do
      begin
        g.mount_ro(mp[1], mp[0])
      rescue Guestfs::Error => msg
        printf("%s (ignored)\n", msg)
      end
    end
  
    # Print basic information about the operating system.
    printf("  Product name: %s\n", g.inspect_get_product_name(root))
    printf("  Version:      %d.%d\n",
           g.inspect_get_major_version(root),
           g.inspect_get_minor_version(root))
    printf("  Type:         %s\n", g.inspect_get_type(root))
    printf("  Distro:       %s\n", g.inspect_get_distro(root))
    printf("  Arch:         %s\n", g.inspect_get_arch(root))
    printf("  Hostname:     %s\n", g.inspect_get_hostname(root))
    printf("  Drive Mappings:\n")
    if g.inspect_get_type(root) == "windows"
      printf("   %s\n", g.inspect_get_drive_mappings(root))
    else
      printf("   %s\n", g.inspect_get_mountpoints(root))
    end
  
    # If /etc/issue.net file exists, print up to 3 lines.
    filename = "/etc/issue.net"
    if g.is_file filename and g.inspect_get_type(root) =~ /inux/ then
      printf("--- %s ---\n", filename)
      lines = g.head_n(3, filename)
      for line in lines do
        puts line
      end
    end
  
    # Unmount everything.
    g.umount_all()
  end
end 

def openstack_get_hypervisors oscreds
    printf("Openstack Username: %s\n",oscreds.username);
    # hypervisors = ["bob", "john", "moe"]
    # fog doesn't yet have hypervisor-list api support
    *hypervisors = `nova hypervisor-list | grep -v "Hypervisor hostname" | grep -v "+----+" | awk '{ print $4 }'`
    return hypervisors
end

def openstack_sshfs_mount hypervisor
end

def openstack_sshfs_unmount hypervisor
end

# Import OpenStack credentials
oscreds = OsCreds.new

# Exit if not running as root
if ENV['USER'] != "root" 
    printf("openstack-guest-inspect.rb must be run as root!\n");
    printf("Exiting!\n");
    exit 1;
end

# Exit if not admin credentials for OpenStack
if (oscreds.username != "admin") 
    printf("Openstack Username: %s != admin! You must have OpenStack admin privilages\n",oscreds.username);
    printf("Exiting!\n");
    exit 1;
end

# Get hypervisor list
oshypes = openstack_get_hypervisors(oscreds)
for oshype in oshypes do
    puts oshype
end

# Mount hypervisor

# Find and inspect nova "disks"
novadirs = Dir["/var/lib/nova/instances/**/disk"]
for ndisk in novadirs do
    results = ndisk.match(/instances\/(.*)\/disk/)
    ninstance = results.captures[0]
    printf("Instance: %s\n", ninstance)
    openstack_guest_inspect(ndisk)
    puts
end

# Unmount hypervisor
