<?php

/**
 * Custom Config GUI Controller
 */

namespace OPNsense\CustomConfig;

use OPNsense\Base\IndexController as BaseIndexController;

class IndexController extends BaseIndexController
{
    /**
     * Default index - redirect to VPN bypass
     */
    public function indexAction()
    {
        $this->view->pick('OPNsense/CustomConfig/vpnbypass');
        $this->view->formVpnbypass = $this->getForm('vpnbypass');
    }

    /**
     * VPN Bypass page
     */
    public function vpnbypassAction()
    {
        $this->view->pick('OPNsense/CustomConfig/vpnbypass');
        $this->view->formVpnbypass = $this->getForm('vpnbypass');
    }

    /**
     * Monit Process Monitor page
     */
    public function monitprocessAction()
    {
        $this->view->pick('OPNsense/CustomConfig/monitprocess');
        $this->view->formMonitprocess = $this->getForm('monitprocess');
        $this->view->formDialogProcess = $this->getForm('dialogProcess');
    }

    /**
     * Custom Files page
     */
    public function customfilesAction()
    {
        $this->view->pick('OPNsense/CustomConfig/customfiles');
        $this->view->formDialogFile = $this->getForm('dialogFile');
    }
}
