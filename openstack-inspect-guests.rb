#! /usr/bin/ruby -w

#########################################################################
# Script: openstack-inspect-guests.rb                                   #
# Version: 0.4.0                                                        #
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
require 'optparse'

module OSInspect

  class OsCreds 
    # Get default credentials from environment
    def initialize()
      @username = ENV['OS_USERNAME']
      @tenant_name = ENV['OS_TENANT_NAME']
      @password = ENV['OS_PASSWORD']
      @auth_url = ENV['OS_AUTH_URL']
      @region_name = ENV['OS_REGION_NAME']
    end
    attr_reader :username, :tenant_name, :password, :auth_url, :region_name
    attr_writer :username, :tenant_name, :password, :auth_url, :region_name
  end

  class OsHypervisors
    def initalize()
      @hypervisors = []
    end
    attr_reader :hypervisors
    attr_writer :hypervisors
  end

  class OsGuest
    def initalize()
      @os = ""
      @vendor = ""
      @product = ""
      @version = ""
      @type = ""
      @distro = ""
      @arch = ""
      @hostname = ""
      @drives = {}
    end
    attr_reader :os, :vendor, :product, :version, :type, :distro, :arch, :hostname, :drives
    attr_writer :os, :vendor, :product, :version, :type, :distro, :arch, :hostname, :drives
  end


  def OSInspect.inspect_disk disk  
    guest = OsGuest.new
    g = Guestfs::Guestfs.new
    # Attach the disk image read-only to libguestfs.
    g.add_drive_opts(disk, :readonly => 1)
  
    # Run the libguestfs back-end.
    g.launch
  
    # Ask libguestfs to inspect for operating systems.
    roots = g.inspect_os
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
    
      # Set basic information about the guest
      guest.product = g.inspect_get_product_name(root);
      guest.type = g.inspect_get_type(root);
      guest.version = sprintf("%d.%d",
        g.inspect_get_major_version(root),
        g.inspect_get_minor_version(root))
      guest.distro = g.inspect_get_distro(root);
      guest.arch = g.inspect_get_arch(root);
      guest.hostname = g.inspect_get_hostname(root);
      if g.inspect_get_type(root) == "windows"
        guest.drives = g.inspect_get_drive_mappings(root);
      else
        guest.drives = g.inspect_get_mountpoints(root);
      end
  
      ## If /etc/issue.net file exists, print up to 3 lines.
      #filename = "/etc/issue.net"
      #if g.is_file filename and g.inspect_get_type(root) =~ /inux/ then
      #  printf("--- %s ---\n", filename)
      #  lines = g.head_n(3, filename)
      #  for line in lines do
      #    puts line
      #  end
      #end
  
      # Unmount everything.
      g.umount_all
    end
    return guest
  end 

  def OSInspect.get_hypervisors oscreds
    # debug: printf("Openstack Username: %s\n",oscreds.username);
    # fog doesn't yet have hypervisor-list api support! Ugh
    *hypervisors = `nova hypervisor-list | grep -v "Hypervisor hostname" | grep -v "+----" | awk '{ print $4 }'`
    return hypervisors
  end

  def OSInspect.main

    # Exit if not running as root
    if ENV['USER'] != "root" 
      printf("openstack-guest-inspect.rb must be run as root!\n");
      printf("Exiting!\n");
      exit 1;
    end
    
    oscreds = OsCreds.new
    options = {}
    options[:all_hypes] = false

    # Parse CLI options
    opt_parser = OptionParser.new do |opt|
      opt.banner = "Usage: openstack-inspect-guests [-a || HYPERVISORS]"
      opt.separator  ""
      opt.separator  "Arguments:"
      opt.separator  "     HYPERVISORS   The hostnames or ip addesses of"
      opt.separator  "                   the hypervisors to process."
      opt.separator  ""
      opt.separator  "Options"
      opt.separator  "     -a     Query hypervisor list from Nova and process every hypervisor"
      opt.separator  "     -h     Help"
      opt.separator  ""
      opt.separator  "     --os-username <auth-user-name>      Defaults to env[OS_USERNAME]."
      opt.separator  "     --os-password <auth-password>       Defaults to env[OS_PASSWORD]."
      opt.separator  "     --os-tenant-name <auth-tenant-name> Defaults to env[OS_TENANT_NAME]."
      opt.separator  "     --os-auth-url <auth-url>            Defaults to env[OS_AUTH_URL]."
      opt.separator  "     --os-region-name <region-name>      Defaults to env[OS_REGION_NAME]."
      opt.separator  ""

      opt.on("-a","Process all hypervisors") do
        options[:all_hypes] = true;
      end

      opt.on("--os-username","--os-username <auth-user-name>") do |username|
        oscreds.username = username
      end
      opt.on("--os-tenant-name","--os-tenant-name <auth-tenant-name>") do |tenant_name|
        oscreds.tenant_name = tenant_name
      end
      opt.on("--os-auth-url","--os-auth-url <auth-url>") do |auth_url|
        oscreds.auth_url = auth_url
      end
      opt.on("--os-region-name","--os-region-name <region-name>") do |region_name|
        oscreds.region_name = region_name
      end
      opt.on("--os-password","--os-password <auth-password>") do |password|
        oscreds.password = password
      end
      opt.on("-h","--help","help") do
        puts opt_parser
      end
    end

    opt_parser.parse!

    if (ARGV[0])
      *oshypes = ARGV
    elsif (options[:all_hypes])
      # Exit if not admin credentials for OpenStack
      if (oscreds.username != "admin") 
        printf("Openstack Username: %s != admin! You must have OpenStack admin privilages\n",oscreds.username);
        printf("Exiting!\n");
        exit 1;
      end
      oshypes = OSInspect.get_hypervisors(oscreds)
    else
      puts opt_parser
      exit 1
    end
    
    for oshype in oshypes do
      # Mount hypervisor
      oshype = oshype.chomp
      printf("Mounting hypervisor: %s\n", oshype)
      unless system("sshfs root\@#{oshype}\:/var/lib/nova /var/lib/nova") 
        printf("Failed to mount hypervisor %s\n",oshype);
        printf("Exiting\n");
        exit 1;
      end
      # Find and inspect nova "disks"
      novadirs = Dir["/var/lib/nova/instances/**/disk"]
      instances = {}
      for ndisk in novadirs do
        results = ndisk.match(/instances\/(.*)\/disk/)
        ninstance = results.captures[0]
        printf("Processing: %s ... ", ninstance)
        instances[ninstance] = OsGuest.new
        starttime = Time.now.to_i
        instances[ninstance] = OSInspect.inspect_disk(ndisk)
        endtime = Time.now.to_i
        printf("[%d seconds]\n", endtime-starttime)
      end

      # Output 
      instances.each_key do |instance|
        printf("Instance %s\n", instance)
        printf("  Product name: %s\n", instances[instance].product)
        printf("  Type:         %s\n", instances[instance].type)
        printf("  Version:      %s\n", instances[instance].version)
        printf("  Distro:       %s\n", instances[instance].distro)
        printf("  Arch:         %s\n", instances[instance].arch)
        printf("  Hostname:     %s\n", instances[instance].hostname)
        printf("  Drives:       %s\n", instances[instance].drives)
      end
      # Unmount hypervisor
      # TODO: Need to fix this unmount. Complains dev is busy
      system("fusermount -u -z /var/lib/nova")
    end
  end
end
if __FILE__ == $0
  OSInspect.main
end
