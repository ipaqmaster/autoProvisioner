## autoProvisioner

A script for automatically installing guests to vSphere clusters by uploading a custom iPXE ISO for them to boot which targets a given http server presenting the required ISO content over the network, mounted or otherwise. It has helped me provision new guests throughout the year with minimal input featuring a collection of templates and scripts for iPXE HTTP boot injection, kickstart scripts for UEFI and a main terraform script invoked for uploading the ISO and initializing the installation of a guest with it.

At the moment I've been working with CentOS 7 and Rocky 9.2 on VMWare clusters so the script currently supports installing those to a vSphere target.

There is also loose support for iPXE booting an Archlinux ISO too however the supplied `ARCH_202307.cfg` file is only a stub from when I was testing it at the time and won't complete an installation on its own yet. I use Arch extensively and plan to add support to this script later on.

### Getting started

To start using this you'll need a webserver which allows plaintext access and a ISO/ subdirectory with either mounted or extracted ISOs inside in directories named after their partition `LABEL`. Mounting is much more storage efficient especially in my case, using a VM with many attached ISOs for this purpose.

The sister project [isoManager](https://github.com/ipaqmaster/isoManager) can be used to automatically handle this as it mounts ISO's on-demand with autofs and reacts to changes in `/dev/sr*` and `/dev/loop*` for automatically adding directories as it detects ISOs being attached/detached/looped or physical CDROM drives receiving a medium, all making for a passive storage-efficient solution for presenting the ISOs.

The ISO directory should be created under this webroot and a kickstarts/ subdirectory should also be made in the webroot for the script and installation guest to reference.

The guest's installation process is started by booting the special iPXE UEFI ISO made especially for it and referring to the webserver for the RedHat-Special `inst.repo=` and `ks=` kernel arguments to complete an installation over the network with the custom variables handled in the script.


#### Requirements / Environment

1. A Linux VM/Host to run this on - accessible to your intended installation guests and their network.

2. A webroot accessible by http for RHEL guest installation processes to read  their kickstart file and download signed packages over the network for their initial installation.

2. Mounted or extracted ISOs readable under the webroot

3. a vSphere host to make the installation to. Plus credentials with access to upload ISOs and create/install guests on said cluster.

##### Packages

1. `terraform`
2. `dialog` (If one intends to use the script's text-graphics configuration dialog)
3. The "Development Tools" package for your system (To compile an iPXE UEFI ISO)

The script will fetch the [iPXE](https://github.com/ipxe/ipxe) source automatically.

#### Usage

Upon calling `./main` for the first time with all dependencies installed the script will prompt for information regarding the environment with some default examples set.

Upon continuing it will write these custom values to a file (.vars) in the local directory for future runs and it will then check for a directory of mounted/extracted ISOs and present with an option to pick which one to install.

At the current time only `CentOS 7 x86_64` and `Rocky-9-2-x86_64-dvd` are supported. These names are determined by their cdrom (/ISO) partition LABEL, which can be easily auto-mapped with [isoManager](https://github.com/ipaqmaster/isoManager).

At this point the script will and prepare a kickstart cfg file for the new guest to reference for its installation and it will compile an EFI iPXE ISO to be uploaded to the guest for it to target the specified.

After compiling, Terraform will prompt for the vSphere user's password and a prompt on whether or not to continue. Continuing will upload the custom ISO and define a guest with it attached, and boot. After 7 or so minutes of RHEL-kickstarting it should return claiming the guest installation were successful.

##### Extra

The script looks for a `domain.internal.post` file with the search-domain given to the guest. If detected it will include the file's content in the %POST section of a RHEL-based guest's kickstart allowing for domain-custom actions to be performed. I use this file to install salt-minion and point to the right salt-master based on the minion's environment.

#### Optional arguments

`-postinjectfiles`/`-post-inject-files`

This can be used to specify additional %POST installation scripts to be concatenated into %POST section of the guest's kickstart file. If a file specified is not listed the script will error and exit.

`-skipvarsiffilled`/`-skip-vars-if-filled`

This can be used if the `.vars` file is already prepped for run or has been prepared by an external application. I added this flag for calling this project from Rundeck's web interface.

`-image`/`-iso`

This can be used to specify the intended ISO without the graphical prompt. If the given ISO LABEL is not present the script will exec

`-passwd`/`-p`/`-password`

This can be used to pass in the vSphere user's password into terraform automatically.

### Plans

* Tidy up and standardize the script some more
* Improve arguments for autonomous calling.
* Add more arguments
* Variablize more bits and pieces.


### The journey (fluff)

#### Cause, Limitations

I've found myself maintaining an environment which has a Windows Deployment Server for PXE booting and installing Windows across the broadcast domain. The environment has an older version of [Foreman](https://github.com/theforeman/foreman) for managing Linux repositories and hosts with an option to provision new hosts automatically. While Foreman supports installing new guests with PXE - The code expects Foreman to be the networks one and only PXE server. A role already filled by WDS.

This Foreman installation had been configured to use a VMWare machine template - a pre-installed CentOS 7 VM "base" it clones and modifies in its own way. Likely done to work around the above limitation.

With Foreman and the built-in [Foreman_Bootdisk](https://github.com/theforeman/foreman_bootdisk) plugin you *can* begin a new guest installation using a small bootdisk ISO however the feature claims to not support UEFI for some reason. There is also another option to use a FULL boot-disk which seems to be much larger in size but features the same problem of an explicit lack of UEFI-boot support. I don't understand the cause for this arbitrary limitation as in very early testing I was able to boot UEFI with iPXE just fine. With that, I started writing my own solution.

After much testing I was unable to get Foreman to budge on the UEFI IPXE ISO network boot situation and also noticed these ISO-based installation options won't automatically upload themselves to a vSphere Datastore Cluster nor create a VM with them attached. So it would still come back to some manual input in the end (Or getting very familiar with vSphere's API for a from-scratch external wrapper script.)

#### Goals

I wanted to avoid using the "Existing VM template" solution as the golden-image would age potentially becoming a security risk down the line, and the specifications of any new VM were dictated by the settings on this template VM which feels nasty. What I wanted was a solution to create new VMs, up to date out of the box and [salted](https://github.com/saltstack/salt) shortly after their installation into the SOE.

WDS is genuinely being used on the network so it can't be uprooted and I was strongly avoiding the idea of some "Linux provisioning VLAN" just for guests to getprovisioned in before shortly being re-configured into their true network (Or dual adapters..) all of which sounded awful. Nor did I want to settle for some DHCP/BOOTP special-case hackery.

After hacking, slashing and discussing Foreman limitations I gave up and made this project to work around the multiple-PXE server limitation problem I'm facing with the goal of touching as few pieces as possible after hitting "Go" and being able to log into a finished installation.

#### PXE booting a distro

##### Annoyances

Once you've got the very explicit set of arguments a distro requires and don't have a single character out of place - PXE booting various distros is super eas. I've found each major distro have their own wild west of booting and unattended installation implementations at the mercy of whoever it was up to for implementing them. This experience has left me more than happy to push this repo publicly as a resource for others on their own UEFI RHEL-like unattended installations, targeted iPXE UEFI ISO image building and otherwise.

RedHat's documentation for network booting and kickstart scripting is a mess of current and outdated documentation pages which don't make the version obvious without scrolling far up the sidebar while all looking *nearly* identical. Many flags have inadiquite documentation for UEFI installations and there is no rock solid documentation for partitioning UEFI hosts - Not without experiencing countless errors duing ks runtime and having to search up the error only to find countless threads of others sailing this same sea.

##### Inconsistencies

Network booting the kernel needs `ip=dhcp` before any of the PXE boot arguments which varying distro to distro can be used. Given the network-boot argument differences even in different versions of the same distros it can be a pain to get a working network boot example and while loading the installer initramfs to kick off an install. I used QEMU attached to a network bridge to test PXE booting CentOS, RHEL9 and Archlinux with back to back attempts instead of the overhead in trying to provision a real vSphere guest each time, which helped trumendously.

Modern RHEL-based distros use kernel args such as `inst.repo=`, `inst.ks=` and `boot=live:xxx` plus a few others for PXE booting from a remote-mounted ISO. CentOS7 uses the old `ks=` argument which was dropped instead of kept alongside the newer variant. And Archlinux takes their own invention of boot arguments `archiso_http_srv=`, `archisobasedir=` and `script=` for the remote script to be executed run. One harmless forwardslash out of place and none of these will boot.

The regular boot methods for these distributions do all sorts of diffrent tricks from the bootloader to load up their initramfs from the ISO. Some expect the ISO to mount and then either use the resulting data directly or abstract further with some cowspace file and then open that up - Others mount *a 'secret' second partition of an ISO, visible when mapped rather than accessed as a CDROM* and many more whacky implementations which vary between every major distro none of which include the above arguments which must be hunted for in many different versions of documentation.

RedHat's documentation for unattended installations (Kickstart) and the many various supported, dropped, legacy and non-functional flags to make the installation medium boot using a HTTP source - Let alone carefully crafting iPXE arguments another layer down to fetch the right kernel image over HTTP and boot it in UEFI mode, *plus* including the required ks= boot a RHEL kernel over http *and* specifying arguments without a single forwad-slash out of place 


the kernel plus the flags reqired over HTTP which may or may not appear in the ISO's own startup entries in the bootloader configuration based on whether they access ISOs or some cowspace image pulled from the ISO onfiguration and the exact requirements to network-boot a Linux kernel over the network from a mounted ISO, plus the arbitrary RedHat arguments to then reference the ISO installation root over the network (Without throwing errors over some missing manifest) quite frustrating and this project also helped serve as a way to provide readily accessible examples on how others could pull off network-booting various Linux ISOs with with their own quirks.
