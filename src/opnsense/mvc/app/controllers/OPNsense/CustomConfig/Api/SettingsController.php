<?php

/**
 * Custom Config Settings API Controller
 */

namespace OPNsense\CustomConfig\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Config;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'customconfig';
    protected static $internalModelClass = 'OPNsense\CustomConfig\CustomConfig';

    /**
     * Get VPN Bypass settings
     * @return array
     */
    public function getVpnbypassAction()
    {
        return ['vpnbypass' => $this->getModel()->vpnbypass->getNodes()];
    }

    /**
     * Set VPN Bypass settings
     * @return array
     */
    public function setVpnbypassAction()
    {
        $result = array("result" => "failed");
        if ($this->request->isPost()) {
            $mdl = $this->getModel();
            $post = $this->request->getPost("vpnbypass");

            // Set individual fields directly (setNodes doesn't work for container fields)
            if (isset($post['enabled'])) {
                $mdl->vpnbypass->enabled = (string)$post['enabled'];
            }
            if (isset($post['domains'])) {
                $mdl->vpnbypass->domains = (string)$post['domains'];
            }
            if (isset($post['gateway'])) {
                $mdl->vpnbypass->gateway = (string)$post['gateway'];
            }
            if (isset($post['gateway6'])) {
                $mdl->vpnbypass->gateway6 = (string)$post['gateway6'];
            }
            if (isset($post['updateinterval'])) {
                $mdl->vpnbypass->updateinterval = (string)$post['updateinterval'];
            }

            $valMsgs = $mdl->performValidation();
            foreach ($valMsgs as $field => $msg) {
                if (!array_key_exists("validations", $result)) {
                    $result["validations"] = array();
                }
                $result["validations"]["vpnbypass." . $msg->getField()] = $msg->getMessage();
            }
            if (count($valMsgs) == 0) {
                $mdl->serializeToConfig();
                Config::getInstance()->save();
                $result["result"] = "saved";
            }
        }
        return $result;
    }

    /**
     * Get Monit Process settings
     * @return array
     */
    public function getMonitprocessAction()
    {
        return ['monitprocess' => $this->getModel()->monitprocess->getNodes()];
    }

    /**
     * Set Monit Process settings
     * @return array
     */
    public function setMonitprocessAction()
    {
        $result = array("result" => "failed");
        if ($this->request->isPost()) {
            $mdl = $this->getModel();
            $post = $this->request->getPost("monitprocess");

            // Set individual fields directly (setNodes doesn't work for container fields)
            if (isset($post['enabled'])) {
                $mdl->monitprocess->enabled = (string)$post['enabled'];
            }

            $valMsgs = $mdl->performValidation();
            foreach ($valMsgs as $field => $msg) {
                if (!array_key_exists("validations", $result)) {
                    $result["validations"] = array();
                }
                $result["validations"]["monitprocess." . $msg->getField()] = $msg->getMessage();
            }
            if (count($valMsgs) == 0) {
                $mdl->serializeToConfig();
                Config::getInstance()->save();
                $result["result"] = "saved";
            }
        }
        return $result;
    }

    /**
     * Search Monit processes
     * @return array
     */
    public function searchProcessAction()
    {
        return $this->searchBase('monitprocess.processes', array('name', 'matchpattern', 'startcmd'));
    }

    /**
     * Get a single Monit process entry
     * @param string $uuid
     * @return array
     */
    public function getProcessAction($uuid = null)
    {
        return $this->getBase('process', 'monitprocess.processes', $uuid);
    }

    /**
     * Add a Monit process entry
     * @return array
     */
    public function addProcessAction()
    {
        return $this->addBase('process', 'monitprocess.processes');
    }

    /**
     * Update a Monit process entry
     * @param string $uuid
     * @return array
     */
    public function setProcessAction($uuid)
    {
        return $this->setBase('process', 'monitprocess.processes', $uuid);
    }

    /**
     * Delete a Monit process entry
     * @param string $uuid
     * @return array
     */
    public function delProcessAction($uuid)
    {
        return $this->delBase('monitprocess.processes', $uuid);
    }

    /**
     * Search Custom files
     * @return array
     */
    public function searchFileAction()
    {
        return $this->searchBase('customfiles.files', array('enabled', 'name', 'filepath'));
    }

    /**
     * Get a single Custom file entry
     * @param string $uuid
     * @return array
     */
    public function getFileAction($uuid = null)
    {
        return $this->getBase('file', 'customfiles.files', $uuid);
    }

    /**
     * Add a Custom file entry
     * @return array
     */
    public function addFileAction()
    {
        return $this->addBase('file', 'customfiles.files');
    }

    /**
     * Update a Custom file entry
     * @param string $uuid
     * @return array
     */
    public function setFileAction($uuid)
    {
        return $this->setBase('file', 'customfiles.files', $uuid);
    }

    /**
     * Delete a Custom file entry
     * @param string $uuid
     * @return array
     */
    public function delFileAction($uuid)
    {
        return $this->delBase('customfiles.files', $uuid);
    }
}
