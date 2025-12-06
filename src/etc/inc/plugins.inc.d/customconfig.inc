<?php

/**
 * Custom Config plugin integration
 */

function customconfig_services()
{
    global $config;
    $services = array();

    // Only show VPN Bypass service if enabled
    if (isset($config['OPNsense']['CustomConfig']['vpnbypass']['enabled']) &&
        $config['OPNsense']['CustomConfig']['vpnbypass']['enabled'] == '1') {

        // DNS Sniffer is the actual daemon service
        $services[] = array(
            'description' => gettext('VPN Bypass DNS Sniffer'),
            'configd' => array(
                'start' => array('customconfig vpnbypass_sniffer_start'),
                'stop' => array('customconfig vpnbypass_sniffer_stop'),
                'restart' => array('customconfig vpnbypass_sniffer_stop', 'customconfig vpnbypass_sniffer_start'),
            ),
            'name' => 'customconfig_vpnbypass_sniffer',
            'pidfile' => '/var/run/vpnbypass_sniffer.pid',
        );
    }

    return $services;
}

function customconfig_cron()
{
    global $config;

    $jobs = array();

    // Check if VPN bypass is enabled
    if (isset($config['OPNsense']['CustomConfig']['vpnbypass']['enabled']) &&
        $config['OPNsense']['CustomConfig']['vpnbypass']['enabled'] == '1') {

        $interval = '*/15'; // Default
        if (isset($config['OPNsense']['CustomConfig']['vpnbypass']['updateinterval'])) {
            $interval = $config['OPNsense']['CustomConfig']['vpnbypass']['updateinterval'];
        }

        // Use autocron format: array(command, minutes, hours, days, months, weekdays)
        $jobs[]['autocron'] = array(
            '/usr/local/opnsense/scripts/OPNsense/CustomConfig/vpnbypass.sh update',
            $interval
        );
    }

    return $jobs;
}

function customconfig_firewall(\OPNsense\Firewall\Plugin $fw)
{
    global $config;

    // Check if VPN bypass is enabled
    if (!isset($config['OPNsense']['CustomConfig']['vpnbypass']['enabled']) ||
        $config['OPNsense']['CustomConfig']['vpnbypass']['enabled'] != '1') {
        return;
    }

    // Get the IPv4 gateway
    $gateway = 'WAN_DHCP';
    if (isset($config['OPNsense']['CustomConfig']['vpnbypass']['gateway'])) {
        $gateway = $config['OPNsense']['CustomConfig']['vpnbypass']['gateway'];
    }

    // Get the IPv6 gateway
    $gateway6 = 'WAN_DHCP6';
    if (isset($config['OPNsense']['CustomConfig']['vpnbypass']['gateway6'])) {
        $gateway6 = $config['OPNsense']['CustomConfig']['vpnbypass']['gateway6'];
    }

    $logDefault = !isset($config['syslog']['nologdefaultpass']);

    // Register IPv4 firewall rule for VPN bypass
    // Priority 1 = early in ruleset, before VPN routing rules
    $fw->registerFilterRule(
        1,
        array(
            'direction' => 'in',
            'to' => '<customconfig_vpnbypass>',
        ),
        array(
            'type' => 'pass',
            'interface' => 'lan',
            'ipprotocol' => 'inet',
            'quick' => true,
            'gateway' => $gateway,
            'log' => $logDefault,
            '#ref' => 'ui/customconfig/vpnbypass',
            'descr' => 'Custom Config - VPN Bypass (IPv4)',
        )
    );

    // Register IPv6 firewall rule for VPN bypass
    $fw->registerFilterRule(
        1,
        array(
            'direction' => 'in',
            'to' => '<customconfig_vpnbypass>',
        ),
        array(
            'type' => 'pass',
            'interface' => 'lan',
            'ipprotocol' => 'inet6',
            'quick' => true,
            'gateway' => $gateway6,
            'log' => $logDefault,
            '#ref' => 'ui/customconfig/vpnbypass',
            'descr' => 'Custom Config - VPN Bypass (IPv6)',
        )
    );
}

function customconfig_xmlrpc_sync()
{
    $result = array();
    $result['id'] = 'customconfig';
    $result['section'] = 'OPNsense.CustomConfig';
    $result['description'] = gettext('Custom Configuration');
    return array($result);
}
