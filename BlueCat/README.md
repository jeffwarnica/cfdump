# BlueCat

## General Information

| Name      | BlueCat |
| --- | --- | --- |
| License   | GPL v2 (see LICENSE file) |
| Version   | 1.0 |

## Author
| Name      | E-mail |
| --- | --- |
| Jeff Warnica| jwarnica@redhat.com |

## Install
Create Namespace, class, schema, instances. Copy and paste into new methods

## Notes

Create class schema per:

| Name | Notes |
| --- | --- |
| targetDNSZoneId | ObjectID of the DNS zone to create records |
| targetDNSDomain | String, DNS zone name of target zone |
| targetDNSViewId | ObjectID of DNS view (would be like "internal", "public", etc. |
| targetNetworkCIDR | x.x.x.x/zz |
| targetNetworkParentId | ObjectID of target network to create records |
| configurationName | String, name of highest level "configuration" |
| username | username |
| password | type=password, password |
| servername | server for SOAP calls |
| method1 | type=method, each instance being register\|release |

Both the scripts can run from the command line, to test registering and releasing from Bluecat, but require some inline
configuration. This should be sufficient to test the configuration, however, without running entire provisions/retirements
through the UI.
