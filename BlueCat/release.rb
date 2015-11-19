###################################
#
# CFME Automate Method: BlueCat/release
#
# Notes: This method uses a SOAP/XML call to BlueCat Proteus to delete IP Address and associated hostname
#
# - Gem requirements: savon -v 2.2.0
# - Inputs: $evm.root['miq_provision']
#
# - Free bonus: Can be run from the command line with some inline configuration
###################################
begin
  unless $evm.nil?
    $IN_CF = true
    $evm.log(:info, "DETECTED BlueCat/release is running inside Cloudforms")
  end

  def log(level, message)
    @method = 'BlueCat/release'
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

  unless $IN_CF
    log(:info, 'Running from command line, setting up some sample data')

    if ARGV.count != 2
      raise "Give me two arguments: hostname ipaddress"
    end
    hostname = ARGV.shift
    ip = ARGV.shift

    servername = ''
    username = ''
    password = ''
    configurationName = ''
    targetNetworkParentId = 15450481;
    # targetNetworkCIDR = '10.7.252.0/23'
    #
    targetDNSViewId = 1213170;
    targetDNSZoneId = 1229292;
    # targetDNSDomain = "uhn.ca"
  else
    dump_root

    #Get provisioning object
    prov = $evm.root['miq_provision']
    vm = $evm.root['vm']

    log(:info, "vm: #{vm.inspect}")
    vm.attributes.sort.each { |k, v| log(:info, "VM Attribute: #{k}\t: #{v}") }
    
    hostname = vm.name
    ip = vm.ipaddresses.first
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

  #target DNS view ID
  targetDNSViewId  ||= $evm.object['targetDNSViewId']

  #zoneID
  targetDNSZoneId ||= $evm.object['targetDNSZoneId']

  log(:info, "IMPORTANT DATA being used: #{servername}/#{username}/password/#{configurationName}/#{targetNetworkParentId}/#{targetDNSViewId}/#{hostname}/#{ip}/")


  # Configure HTTPI gem
  HTTPI.log_level = :info # changing the log level
  HTTPI.log = false # diable HTTPI logging
  HTTPI.adapter = :net_http # [:httpclient, :curb, :net_http]

  # Configure Savon gem
  $client = Savon.client(
      wsdl: "http://#{servername}/Services/API?wsdl",
      log: false, # disable Savon logging
      log_level: :debug, # changing the log level
      pretty_print_xml: true,
      strip_namespaces: true
  )

  def deleteFromBC(objectId)
    log(:info, "GOING TO DELETE <#{objectId}>")
    msg = {'objectId' => objectId}
    cfgReply = $client.call(:delete, :message => msg, cookies: $auth_cookies)
    # log(:info, "cfgReply: <#{cfgReply.inspect}>")
    properties = cfgReply.body[:delete_response]
    log(:info, "Deleted objectId:<#{objectId}>")
  end

  # Log into BlueCat Proteus
  msg = {'username' => username, 'password' => password}
  authReply = $client.call(:login, :message => msg)
  $auth_cookies = authReply.http.cookies

  # log(:info, 'Auth Reply:<#{authReply.inspect}>')

  #get 'Configuration' object (named 'Production')
  msg = {'parentId' => 0, 'name' => configurationName, 'type' => 'Configuration'}
  cfgReply = $client.call(:get_entity_by_name, :message => msg, cookies: $auth_cookies)
  configuratonId = cfgReply.body[:get_entity_by_name_response][:return][:id]
  log(:info, "configurationId: <#{configuratonId}>")

  # log(:info, "Searching for DNS entry for hostname: <#{hostname}>")
  # msg = {'parentId' => targetDNSZoneId, 'name'=>hostname, 'type'=>'HostRecord'}
  # cfgReply = $client.call(:get_entity_by_name, :message => msg, cookies: $auth_cookies)
  # # log(:info, "cfgReply: <#{cfgReply.inspect}>")
  # begin
  #   configuratonId = cfgReply.body[:get_entity_by_name_response][:return][:id]
  #   log(:info, "Got a DNS Entry ObjID: #{configuratonId}")
  #   deleteFromBC(configuratonId)
  # rescue
  #   log(:warn, "Something went't wrong finding or deleting DNS entry. Ignoring and proceeding")
  # end

  log(:info, "Searching for IP entry for IP: <#{ip}>")
  msg = {'parentId' => targetNetworkParentId, 'cidr'=>"#{ip}/32", 'type'=>'IP4Address'}
  cfgReply = $client.call(:get_entity_by_cidr, :message => msg, cookies: $auth_cookies)
  # log(:info, "cfgReply: <#{cfgReply.inspect}>")
  begin
    configuratonId = cfgReply.body[:get_entity_by_cidr_response][:return][:id]
    log(:info, "Got a IP Entry ObjID: #{configuratonId}")
    deleteFromBC(configuratonId)
  rescue
    log(:warn, "Something went't wrong finding or deleting IP entry. Ignoring and proceeding")
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
