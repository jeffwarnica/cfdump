###################################
#
# CFME Automate Method: BlueCat/register
#
# Notes: This method uses a SOAP/XML call to BlueCat Proteus to reserve an IP Address, and to set a DNS entry
#  and set the values in the miq_provision object.
# - Gem requirements: savon -v 2.2.0
# - Inputs: $evm.root['miq_provision']
#
# - Free bonus: Can be run from the command line with some inline configuration
###################################
begin
  unless $evm.nil?
    $IN_CF = true
    $evm.log(:info, "DETECTED BlueCat/register is running inside Cloudforms")
  end

  def log(level, message)
    @method = 'BlueCat/register'
    unless $IN_CF
      print "#{level}, #{@method} - #{message}\n"
    else
      $evm.log(level, "#{@method} - #{message}")
    end
  end

  # dump_root
  def self.dump_root()
    log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
    $evm.root.attributes.sort.each { |k, v| log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}") }
    log(:info, "Root:<$evm.root> End $evm.root.attributes")
    log(:info, "")
  end

  # Require Ruby Gem
  gem 'savon', ">=2.1.0"
  require 'savon'
  require 'httpi'
  require 'ipaddress'

  unless $IN_CF
    log(:info, 'Running from command line, setting up some sample data')
    ###
    # SAMPLE DATA FOR COMMAND LINE RUN
    ###
    if ARGV.count != 2
      raise "Give me a couple of arguments, hostname and mac address"
    end
    hostname = ARGV.shift #"FAKE_TEST"
    macAddressToRegister = ARGV.shift #'00:50:56:00:00:00'

    servername = ''
    username = ''
    password = ''
    configurationName = ''
    targetNetworkParentId = 0;
    targetNetworkCIDR = '10.7.252.0/23'

    targetDNSViewId = 0;
    targetDNSDomain = ""
  else

    dump_root

    #Get provisioning object
    prov = $evm.root['miq_provision']
    ws_values = prov.options[:ws_values]
    log(:info, "ws_values: #{ws_values.inspect}")
    hostname = prov.get_option(:vm_target_name)
    macAddressToRegister = prov.get_option(:mac_address)
    targetDNSDomain = ws_values[:dns_domain]
  end

  # Set servername below else use input from model
  servername ||= $evm.object['servername']

  # Set username name below else use input from model
  username ||= $evm.object['username']

  # Set username name below else use input from model
  password ||= $evm.object.decrypt('password')

  # Set the "configuration" name, which is some kind of scope concept for Bluecat
  configurationName ||= $evm.object['configurationName']

  # Set the target networks ID (From the Promethius UI, "IP Space" -> drill down -> "details"-> "Object ID")
  targetNetworkParentId ||= $evm.object['targetNetworkParentId']

  #and the target network, in CIDR notation
  targetNetworkCIDR ||= $evm.object['targetNetworkCIDR']

  #target DNS view ID
  targetDNSViewId  ||= $evm.object['targetDNSViewId']

  log(:info, "IMPORTANT DATA being used: #{servername}/#{username}/password/#{configurationName}/#{targetNetworkParentId}/#{targetNetworkCIDR}/#{hostname}/#{macAddressToRegister}/")

  # Configure HTTPI gem
  HTTPI.log_level = :info # changing the log level
  HTTPI.log = false # diable HTTPI logging
  HTTPI.adapter = :net_http # [:httpclient, :curb, :net_http]

  # Configure Savon gem
  client = Savon.client(
      wsdl: "http://#{servername}/Services/API?wsdl",
      log: false, # disable Savon logging
      log_level: :info, # changing the log level
      pretty_print_xml: true,
      strip_namespaces: true
  )

  # Log into BlueCat Proteus
  msg = {'username' => username, 'password' => password}
  authReply = client.call(:login, :message => msg)
  auth_cookies = authReply.http.cookies

  #get 'Configuration' object (named 'Production')
  msg = {'parentId' => 0, 'name' => configurationName, 'type' => 'Configuration'}
  cfgReply = client.call(:get_entity_by_name, :message => msg, cookies: auth_cookies)
  configuratonId = cfgReply.body[:get_entity_by_name_response][:return][:id]
  log(:info, "configurationId:<#{configuratonId}>")

  #Sigh. Get the network object. The parentID is hard coded here to the ID of 10.0.0.0/8, as the
  #search is non-recursive.

  msg = {'parentId' => targetNetworkParentId, 'cidr' => targetNetworkCIDR, 'type' => 'IP4Network'}
  cfgReply = client.call(:get_entity_by_cidr, :message => msg, cookies: auth_cookies)
  # log(:info, "cfgReply: <#{cfgReply.inspect}>")
  networkId = cfgReply.body[:get_entity_by_cidr_response][:return][:id]
  properties = cfgReply.body[:get_entity_by_cidr_response][:return][:properties]
  gateway = properties.match(/gateway=(.+?)\|/).captures[0]
  log(:info, "Network ID:<#{networkId}>")
  log(:info, "Network GW:<#{gateway}>")

  #ASSIGN IP ADDRESS
  # assignNextAvailableIP4Address
  msg = {'configurationId' => configuratonId, 'parentId' => networkId, 'macAddress' => macAddressToRegister, 'hostInfo' => hostname, 'action' => 'MAKE_STATIC', 'properties' => nil}
  assignReply = client.call(:assign_next_available_ip4_address, :message => msg, cookies: auth_cookies)
  # log(:info, "cfgReply: <#{assignReply.inspect}>")
  macProperties = assignReply.body[:assign_next_available_ip4_address_response][:return][:properties]
  ipAddress = macProperties.match(/address=(.+?)\|/).captures[0]
  log(:info, "IP Address::<#{ipAddress}>")

  # #Add DNS Host Record
  # msg = { 'viewId'=> targetDNSViewId, 'absoluteName' => "#{hostname}.#{targetDNSDomain}", 'addresses'=>ipAddress, 'ttl'=>0, 'properties'=>''}
  # addDNSReply = client.call(:add_host_record, :message => msg, cookies: auth_cookies)
  # #log(:info, "cfgReply: <#{addDNSReply.inspect}>")
  # recordId = addDNSReply.body[:add_host_record_response][:return]
  # log(:info, "DNS Record ID::<#{recordId}>")


  #HERE WE HAVE THE FOLLOWING SIGNIFICANT THINGS
  #   GENERATED / ASSIGNED
  #     ipAddress
  #     gateway
  # HARDCODED / ASSUMED
  #     targetNetworkCIDR
  #
  #

  netIpAddr = IPAddress::IPv4.new targetNetworkCIDR
  submask= netIpAddr.netmask

  if $IN_CF
    # Assign Networking information
    prov.set_option(:addr_mode, ["static", "Static"])

    prov.set_option(:ip_addr, ipAddress.to_s)
    prov.set_option(:subnet_mask, submask.to_s)
    prov.set_option(:gateway, gateway.to_s)
    prov.set_nic_settings(0, {:ip_addr => ipAddress.to_s, :subnet_mask => submask.to_s, :gateway => gateway.to_s, :addr_mode => ["static", "Static"]})

    log(:info, "Provision Object update: [:ip_addr=>#{prov.options[:ip_addr].inspect},:subnet_mask=>#{prov.options[:subnet_mask]},:gateway=>#{prov.options[:gateway]},:addr_mode=>#{prov.options[:addr_mode]} ]")
  else
    log(:info, "IMPORTANT DATA GENERATED: ipAddress:<#{ipAddress}>, gateway: <#{gateway}>,subnet_mask:<#{submask}>")
  end

  # Exit method
  log(:info, "CFME Automate Method Ended")
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
