###################################
#
# CFME Automate Method for "CMDB" updates
#
# Author: Jeff Warnica <jwarnica@redhat.com>
# License: GPL v3
# Updated: 2015-11-19
#
# Creates a spreadsheet, sftp's to remote server
# (currently with ServiceNow type fields)
#
# recommend you name the method "doit" to match the log
#
# Enclosing Automate Class requires the schema:
#
#   mode                    instance: add|update
#   from_email_address      for failure
#   to_email_address        for failure
#   sftpHost
#   sftpUser
#   sftpPassword            as type: password
#   sftpPath
#   method1                 as type: method, each instance set to however you name this
#
# - Free bonus: Can be run from the command line with some inline configuration, but failure emails won't work
#
###################################
begin
  require 'spreadsheet'
  require 'net/sftp'

  unless $evm.nil?
    $IN_CF = true
    $evm.log(:info, 'DETECTED cmdb_ss_sftp/doit is running inside Cloudforms')
  end

  def log(level, message)
    @method = 'cmdb_ss_sftp/doit'
    unless $IN_CF
      print "#{level}, #{@method} - #{message}\n"
    else
      $evm.log(level, "#{@method} - #{message}")
    end
  end

  # dump_root
  def self.dump_root()
    log(:info, 'Root:<$evm.root> Begin $evm.root.attributes')
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}") }
    log(:info, 'Root:<$evm.root> End $evm.root.attributes')
    log(:info, '')
  end

  unless $IN_CF
    log(:info, 'Running from command line, setting up some sample data')

    sftpHost = 'XXXXX'
    sftpUser = 'XXXXX'
    sftpPassword = 'X'
    sftpPath = '/'

    #fake data
    ci_type = 'Windows Server'
    name= 'myfakeservver.fake.com'

    mode = 'update'
  else

    dump_root

    mode ||= $evm.object['mode']

    unless mode == 'add' || mode == 'update'
      throw('Mode must be add or update')
    end

    log(:info, "Going to #{mode} a record")
    sftpHost ||= $evm.object['sftpHost']
    sftpUser ||= $evm.object['sftpUser']
    sftpPassword ||= $evm.object.decrypt('sftpPassword')
    sftpPath ||= $evm.object['sftpPath']

    if mode == 'add'
      #Get provisioning object
      prov = $evm.root['miq_provision']
      ws_values = prov.options[:ws_values]
      log(:info, "ws_values: #{ws_values.inspect}")

      hostname = prov.get_option(:vm_target_name)
      macAddressToRegister = prov.get_option(:mac_address)
      targetDNSDomain = ws_values[:dns_domain]
      costCenter = ws_values[:cc]

      template = prov.vm_template
      provider = template.ext_management_system
      product = template.operating_system['product_name'].downcase rescue nil

      name = prov.get_option(:vm_target_name)
      ip_addr = prov.get_option(:ip_addr)
      install_status = 'Installed'
      operational_status = 'Operational'
    else
      vm = $evm.root[:vm]
      name = vm.name
      ip_addr = nil
      costCenter = nil
      install_status = 'Retired'
      operational_status = 'Non-Operational'

      dns_tag = vm.tags(:dns_domain)

      #TODO: update this for site specific details
      targetDNSDomain = $evm.vmdb(:classification).find_by_name('dns_domain/uhn_ca').description

      product = vm.operating_system[:product_name]

    end

    case product
      when /suse/i, /centos/i, /rhel/i
        ci_type = 'Linux Server'
      when /windows/i
        ci_type = 'Windows Server'
      else
        log(:warn, "Unknown product: <#{product}>")
    end

  end

  date = Time.now.strftime('%m-%d-%Y')

  Spreadsheet.client_encoding = 'UTF-8'
  book = Spreadsheet::Workbook.new
  sheet1 = book.create_worksheet

  r0 = sheet1.row(0)
  r1 = sheet1.row(1)

  r0[0] = 'u_action'
  r0[1] = 'CI Type'
  r0[2] = 'sys_domain'
  r0[3] = 'company'
  r0[4] = 'name'
  r0[5] = 'u_name_ref'
  r0[6] = 'u_manufacturer_ref'
  r0[7] = 'u_model_id_ref'
  r0[8] = 'u_ip_address_ref'
  r0[9] = 'location'
  r0[10] = 'cost_center'
  r0[11] = 'install_status'
  r0[12] = 'operational_status'
  r0[13] = 'install_date'
  r0[14] = 'due'
  r0[15] = 'u_sla_support_tier'
  r0[16] = 'u_am_category'
  r0[17] = 'u_supported_by_company'
  r0[18] = 'u_virtual_ref'
  r0[19] = 'used_for'

  r1[0] = mode #u_action'
  r1[1] = ci_type #CI Type'
  r1[2] = targetDNSDomain #sys_domain'
  r1[3] = 'University Health Network' #company'
  r1[4] = name #name'
  r1[5] = name #u_name_ref'
  r1[6] = 'VMWARE-[L]' #u_manufacturer_ref'
  r1[7] = 'VIRTUAL-[L]' #u_model_id_ref'
  r1[8] = ip_addr #u_ip_address_ref'
  r1[9] = 'TGH-AOB-03-RM-307' #location'
  r1[10] = costCenter #cost_center'
  r1[11] = install_status #install_status'
  r1[12] = operational_status #operational_status'
  r1[13] = mode == 'add' ? date : '' #install_date'
  r1[14] = mode == 'add' ? '' : date #due'
  r1[15] = 'Non-Medal Server' #u_sla_support_tier'
  r1[16] = 'Virtual Server' #u_am_category'
  r1[17] = 'UHN' #u_supported_by_company'
  r1[18] = 'True' #u_virtual_ref'
  r1[19] = 'Development' #used_for'

  date = Time.now.strftime('%y%m%d%H%M%S')
  #ToCompucom_mmddyyyyhhmm_hostname
  fileName = "ToCompucom_#{date}_#{name}.xls"
  localFilePath = "/tmp/#{fileName}"
  log(:info, "sftp: Saving file to #{localFilePath}")
  book.write localFilePath

  begin
    log(:info, "sftp: Connecting to #{sftpUser} @ #{sftpHost}")
    Net::SFTP.start(sftpHost, sftpUser, :password => sftpPassword) do |sftp|
      remoteFilePath = "#{sftpPath}/#{fileName}"
      log(:info, "sftp: upload(#{localFilePath}, #{remoteFilePath}")
      sftp.upload(localFilePath, remoteFilePath)
    end
  rescue Exception => e
    log(:warn, "File upload error. Ignoring and proceeding. Error was: #{e.message} / #{e.backtrace}")

    to = nil
    to ||= $evm.object['to_email_address']

    # Get from_email_address from model unless specified below
    from = nil
    from ||= $evm.object['from_email_address']

    # email subject
    subject = "CFME Warning: Failed to upload CMDB files for #{name}"

    # Build email body
    body = "There was a failure in uploading the CMDB .xls file to the ServiceNow sftp server.\n\n\n"
    body += "Possibly helpful debugging information follows:\t #{e.message}"

    $evm.execute('send_email', to, from, subject, body)

  end

  # Exit method
  log(:info, 'CFME Automate Method Ended')
  if $IN_CF
    exit MIQ_OK
  end

    # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  if $IN_CF
    exit MIQ_ABORT
  else
    exit 1
  end
end
