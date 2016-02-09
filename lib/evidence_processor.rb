require 'resolv'
require_relative 'build_inspector'
require_relative 'packet_inspector'

class EvidenceProcessor
  KILOBYTE = 1024.0

  SNOOPY_FILTER = [
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant(?:/repo)? filename:/bin/rm\]: rm #{Regexp.escape(VagrantWhisperer::TMP_CMDS)}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/bash\]: bash -c scp -t #{Regexp.escape(VagrantWhisperer::TMP_CMDS)}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/scp\]: scp -t #{Regexp.escape(VagrantWhisperer::TMP_CMDS)}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/bash\]: bash -c bash -l #{Regexp.escape(VagrantWhisperer::TMP_CMDS)}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/bash\]: bash -l #{Regexp.escape(VagrantWhisperer::TMP_CMDS)}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/sudo\]: sudo rdiff-backup --list-increments /backup\n\z~,
    %r~\A\[uid:0 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/rdiff-backup\]: rdiff-backup --list-increments /backup\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/sudo\]: sudo rdiff-backup --include-filelist /tmp/evidence-files\.txt --compare-at-time [^/]+/ /backup\n\z~,
    %r~\A\[uid:0 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/rdiff-backup\]: rdiff-backup --include-filelist /tmp/evidence-files\.txt --compare-at-time [^/]+/ /backup\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/ruby\]: #{Regexp.escape("ruby -e " + BuildInspector::DIFF_RUBY).tr("'", '')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/sudo\]: sudo pkill tcpdump\n\z~,
    %r~\A\[uid:0 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/pkill\]: pkill tcpdump\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/ps\]: ps --sort=lstart -eott,cmd\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/awk\]: awk -F:  \$1 == "Current mirror" {print \$2}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/diff\]: diff -u /backup/home/vagrant/\.bashrc /home/vagrant/\.bashrc\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/sudo\]: sudo cp /var/log/snoopy\.log /evidence\n\z~,
    %r~\A\[uid:0 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/cp\]: cp /var/log/snoopy\.log /evidence\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/cat\]: cat /home/vagrant/\.rvm/(RELEASE|VERSION)\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/grep\]: grep DISTRIB_ID=Ubuntu /etc/lsb-release\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant(?:/repo)? filename:/bin/grep\]: #{Regexp.escape('grep ^\s*rvm .*$ /home/vagrant/.rvmrc')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/ps\]: ps -p \d+ -o ucomm=\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/sed\]: #{Regexp.escape('sed -n -e \#^system_arch=# { s#^system_arch=##;; p; } -e /^$/d')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/sed\]: #{Regexp.escape('sed -n -e \#^system_name=# { s#^system_name=##;; p; } -e /^$/d')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/sed\]: #{Regexp.escape('sed -n -e \#^system_name_lowercase=# { s#^system_name_lowercase=##;; p; } -e /^$/d')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/sed\]: #{Regexp.escape('sed -n -e \#^system_type=# { s#^system_type=##;; p; } -e /^$/d')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/bin/sed\]: #{Regexp.escape('sed -n -e \#^system_version=# { s#^system_version=##;; p; } -e /^$/d')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant(?:/repo)? filename:/bin/sed\]: #{Regexp.escape('sed -e s/-/ /')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant(?:/repo)? filename:/bin/uname\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/home/vagrant/\.rvm/rubies/ruby-[\d\.]+/bin/ruby\]: #{Regexp.escape("ruby -e " + BuildInspector::DIFF_RUBY).tr("'", '')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/awk\]: #{Regexp.escape('awk -F= $1=="DISTRIB_RELEASE"{print $2} /etc/lsb-release')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/dirname\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/dpkg\]: dpkg --print-architecture\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/head\]: head -n 1\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/locale\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant filename:/usr/bin/tr\]: #{Regexp.escape('tr [A-Z] [a-z]')}\n\z~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant(?:/repo)? filename:/usr/bin/which\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant/repo filename:/usr/bin/find\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant/repo filename:/usr/bin/basename\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant/repo filename:/usr/lib/git-core/git\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant/repo filename:/bin/ls\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant/repo filename:/usr/bin/expr\]:~,
    %r~\A\[uid:1000 sid:\d+ tty:\(none\) cwd:/home/vagrant/repo filename:/usr/bin/dirname\]:~,
  ]

  def initialize(evidence_path:, vagrant_ip:, host_whitelist:)
    @evidence_path = File.join(evidence_path, 'evidence')
    @vagrant_ip = vagrant_ip
    @host_whitelist = host_whitelist
  end

  def process
    print_processes
    print_connections
    print_filesystem_changes
    print_running_processes
  end

  private

  def print_processes
    snoopy_path = File.join(@evidence_path, BuildInspector::PROCESSES_FILE)
    lines = IO.readlines(snoopy_path)
    SNOOPY_FILTER.each do |filter|
      lines -= lines.grep(filter)
    end

    perl_lines = lines.select { |l| l.include?('filename:/usr/bin/perl]: /usr/bin/perl -e') }
    require 'digest'
    sha256 = Digest::SHA256.new
    perl_lines.each do |pl|
      idx = lines.find_index(pl)
      next unless idx
      perl = lines[idx..29] * ''
      digest = sha256.hexdigest(perl)
      next unless digest == 'f25df829a02c9b3fc3cba4d4651c9d5c045bd7dbb1958fba91bb79a31ac83c7f'
      lines.slice!(idx..29)
    end

    filtered_path = File.join(@evidence_path, "filtered-commands.txt")
    File.open(filtered_path, 'w') do |f|
      lines.each { |l| f.write(l) }
    end

    puts Printer.yellowify('Filtered commands executed:')
    lines.each { |line| puts "  #{line}"}
  end

  def print_connections
    pcap_file = File.join(@evidence_path, BuildInspector::PCAP_FILE)
    packet_inspector = PacketInspector.new(pcap_file)
    outgoing_packets = packet_inspector.packets_from(@vagrant_ip)

    ips_sizes = outgoing_packets.each_with_object(Hash.new(0)) do |packet, memo|
      memo[packet.ip_dst_readable] += packet.size
    end

    dns_responses = packet_inspector.dns_responses
    address_to_name = dns_responses.each_with_object({}) do |name_addresses, memo|
      name = name_addresses.first
      addresses = name_addresses.last
      addresses.each { |address| memo[address.to_s] = name }
    end

    # Whitelist the DNS' IP also; don't want it showing up
    dns_server = Resolv::DNS::Config.default_config_hash[:nameserver]
    whitelist = @host_whitelist
    whitelist += dns_server if dns_server

    not_in_whitelist = ips_sizes.map { |ip, size| [address_to_name.fetch(ip, ip), ip, size] }
                                .find_all { |hostname, ip, size| !(whitelist.include?(hostname) || whitelist.include?(ip)) }
    return if not_in_whitelist.empty?

    puts Printer.yellowify('Hosts contacted:')
    not_in_whitelist.each do |hostname, ip, size|
      name_ip = "#{hostname} (#{ip})".ljust(60)
      puts "  #{name_ip} #{prettify(size).rjust(10)}"
    end
  end

  def prettify(size)
    return size.to_s + 'B' if size < 1000
    (size / KILOBYTE).round(1).to_s + 'K'
  end

  def print_filesystem_changes
    changes_file = File.join(@evidence_path, BuildInspector::FILESYSTEM_CHANGES_FILE)
    lines = IO.readlines(changes_file)

    # Skip these lines; they are meaningless.
    lines -= [
      "changed: home/vagrant\n",
      "No changes found.  Directory matches archive data.\n",
    ]

    return if lines.empty?

    puts Printer.yellowify('File system changes:')
    lines.each { |line| puts line }
  end

  def print_running_processes
    procs_before_file = File.join(@evidence_path, BuildInspector::PROCESSES_BEFORE_FILE)
    procs_after_file = File.join(@evidence_path, BuildInspector::PROCESSES_AFTER_FILE)

    procs_before = File.readlines(procs_before_file)
    procs_after = File.readlines(procs_after_file)
    new_procs = procs_after - procs_before
    return if new_procs.empty?

    puts Printer.yellowify('New processes running after the build:')
    new_procs.flatten.each do |proc|
      puts "  - #{proc}"
    end
  end
end