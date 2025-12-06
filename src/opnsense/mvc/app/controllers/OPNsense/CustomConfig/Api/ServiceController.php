<?php

/**
 * Custom Config Service API Controller
 * Handles apply/reconfigure actions
 */

namespace OPNsense\CustomConfig\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Core\Config;
use OPNsense\Routing\Gateways;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\CustomConfig\CustomConfig';
    protected static $internalServiceTemplate = 'OPNsense/CustomConfig';
    protected static $internalServiceEnabled = 'vpnbypass.enabled';
    protected static $internalServiceName = 'customconfig';

    /**
     * Reconfigure all custom config items
     * @return array
     */
    public function reconfigureAction()
    {
        $backend = new Backend();
        $response = array();

        // Generate all config files from templates
        $response['template'] = trim($backend->configdRun('template reload OPNsense/CustomConfig'));

        // Apply VPN bypass configuration
        $response['vpnbypass'] = trim($backend->configdRun('customconfig vpnbypass'));

        // Apply Monit configuration
        $response['monit'] = trim($backend->configdRun('customconfig monit'));

        // Apply custom files
        $response['customfiles'] = trim($backend->configdRun('customconfig customfiles'));

        // Reconfigure cron to pick up interval changes
        $response['cron'] = trim($backend->configdRun('cron restart'));

        return $response;
    }

    /**
     * Update VPN bypass IPs (resolve domains)
     * @return array
     */
    public function updateVpnbypassAction()
    {
        $backend = new Backend();
        $response = trim($backend->configdRun('customconfig update_vpnbypass'));
        return array('response' => $response);
    }

    /**
     * Get status of all services
     * @return array
     */
    public function statusAction()
    {
        $backend = new Backend();
        $response = array();
        $response['vpnbypass'] = trim($backend->configdRun('customconfig vpnbypass_status'));
        $response['monit'] = trim($backend->configdRun('customconfig monit_status'));
        return $response;
    }

    /**
     * Get list of available gateways
     * @return array
     */
    public function getGatewaysAction()
    {
        $result = array();
        $gateways = new Gateways();
        foreach ($gateways->getGateways() as $gw) {
            if (!empty($gw['disabled']) || empty($gw['name'])) {
                continue;
            }
            $gwName = $gw['name'];
            $result[$gwName] = array(
                'name' => $gwName,
                'interface' => $gw['interface'] ?? '',
                'gateway' => $gw['gateway'] ?? '',
                'description' => sprintf('%s - %s (%s)', $gwName, $gw['gateway'] ?? 'dynamic', $gw['interface'] ?? '')
            );
        }
        return array('gateways' => $result);
    }

    /**
     * Get resolved IPs from VPN bypass table
     * @return array
     */
    public function getResolvedIpsAction()
    {
        $result = array('ips' => array(), 'count' => 0);
        $output = shell_exec('/sbin/pfctl -t customconfig_vpnbypass -T show 2>/dev/null');
        if ($output) {
            $ips = array_filter(array_map('trim', explode("\n", $output)));
            $result['ips'] = array_values($ips);
            $result['count'] = count($ips);
        }
        return $result;
    }

    /**
     * Get discovered domains from DNS snooping
     * @return array
     */
    public function getDiscoveredDomainsAction()
    {
        $backend = new Backend();
        $response = trim($backend->configdRun('customconfig vpnbypass_discovered'));
        $result = json_decode($response, true);
        if ($result === null) {
            return array('domains' => array(), 'count' => 0);
        }
        return $result;
    }

    /**
     * Clear discovered domains
     * @return array
     */
    public function clearDiscoveredAction()
    {
        $backend = new Backend();
        $response = trim($backend->configdRun('customconfig vpnbypass_clear'));
        return array('response' => $response);
    }

    /**
     * Add a domain to the discovered list
     * @return array
     */
    public function addDiscoveredDomainAction()
    {
        $result = array('result' => 'failed');
        if ($this->request->isPost()) {
            $domain = $this->request->getPost('domain', 'string', '');
            if (!empty($domain)) {
                // Validate domain format
                if (preg_match('/^[a-zA-Z0-9][a-zA-Z0-9\-\.]+[a-zA-Z0-9]$/', $domain)) {
                    $backend = new Backend();
                    $response = trim($backend->configdRun('customconfig vpnbypass_add ' . escapeshellarg($domain)));
                    $result['result'] = 'ok';
                    $result['response'] = $response;
                } else {
                    $result['message'] = 'Invalid domain format';
                }
            } else {
                $result['message'] = 'Domain required';
            }
        }
        return $result;
    }

    /**
     * Get DNS sniffer status
     * @return array
     */
    public function getSnifferStatusAction()
    {
        $backend = new Backend();
        $response = trim($backend->configdRun('customconfig vpnbypass_sniffer_status'));

        $running = (strpos($response, 'is running') !== false);
        $pid = null;
        if (preg_match('/PID:\s*(\d+)/', $response, $matches)) {
            $pid = (int)$matches[1];
        }

        return array(
            'running' => $running,
            'pid' => $pid,
            'response' => $response
        );
    }

    /**
     * Start DNS sniffer
     * @return array
     */
    public function startSnifferAction()
    {
        $backend = new Backend();
        $response = trim($backend->configdRun('customconfig vpnbypass_sniffer_start'));
        return array('response' => $response);
    }

    /**
     * Stop DNS sniffer
     * @return array
     */
    public function stopSnifferAction()
    {
        $backend = new Backend();
        $response = trim($backend->configdRun('customconfig vpnbypass_sniffer_stop'));
        return array('response' => $response);
    }
}
