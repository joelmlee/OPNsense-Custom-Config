{#
 # Custom Config - VPN Bypass
 #}

<script>
    $(document).ready(function() {
        var savedGateway = 'WAN_DHCP';
        var savedGateway6 = 'WAN_DHCP6';

        // Function to populate gateway dropdowns
        function populateGatewayDropdowns(gatewayData) {
            var ipv4Gateways = {};
            var ipv6Gateways = {};

            $.each(gatewayData, function(key, gw) {
                // Check if it's IPv6 (has : in gateway address or key contains 6/V6)
                if (key.indexOf('DHCP6') > -1 || key.indexOf('_V6') > -1 || key.indexOf('_VPN6') > -1 ||
                    key.indexOf('VPNV6') > -1 || (gw['gateway'] && gw['gateway'].indexOf(':') > -1)) {
                    ipv6Gateways[key] = gw;
                } else {
                    ipv4Gateways[key] = gw;
                }
            });

            // Populate IPv4 dropdown - use attribute selector to be safe with dots in IDs
            var select4 = $('select[id="vpnbypass.gateway"]');
            select4.empty();
            $.each(ipv4Gateways, function(key, gw) {
                var opt = $('<option></option>').val(key).text(gw['description']);
                if (key === savedGateway) {
                    opt.prop('selected', true);
                }
                select4.append(opt);
            });
            // Reinitialize selectpicker
            if (select4.hasClass('selectpicker')) {
                select4.selectpicker('refresh');
            }

            // Populate IPv6 dropdown
            var select6 = $('select[id="vpnbypass.gateway6"]');
            select6.empty();
            $.each(ipv6Gateways, function(key, gw) {
                var opt = $('<option></option>').val(key).text(gw['description']);
                if (key === savedGateway6) {
                    opt.prop('selected', true);
                }
                select6.append(opt);
            });
            if (select6.hasClass('selectpicker')) {
                select6.selectpicker('refresh');
            }
        }

        // Load gateways first, then load form
        ajaxGet("/api/customconfig/service/getGateways", {}, function(gwData, status) {
            // Store gateways data
            var gateways = gwData['gateways'] || {};

            // Now get saved settings
            ajaxGet("/api/customconfig/settings/getVpnbypass", {}, function(data, status) {
                if (data && data['vpnbypass']) {
                    savedGateway = data['vpnbypass']['gateway'] || 'WAN_DHCP';
                    savedGateway6 = data['vpnbypass']['gateway6'] || 'WAN_DHCP6';
                }

                // Load form with standard mapper
                mapDataToFormUI({'frm_vpnbypass':"/api/customconfig/settings/getVpnbypass"}).done(function(){
                    formatTokenizersUI();
                    $('.selectpicker').selectpicker('refresh');

                    // Populate gateway dropdowns after form is loaded
                    populateGatewayDropdowns(gateways);
                });
            });
        });

        // Handle domains input - convert spaces/tabs to newlines on blur
        $(document).on('blur', '#vpnbypass\\.domains', function() {
            var val = $(this).val();
            // Replace tabs and multiple spaces with newlines, then clean up multiple newlines
            val = val.replace(/[\t ]+/g, '\n').replace(/\n+/g, '\n').trim();
            $(this).val(val);
        });

        // Load resolved IPs
        function loadResolvedIps() {
            ajaxGet("/api/customconfig/service/getResolvedIps", {}, function(data, status) {
                if (data) {
                    $('#ip-count').text(data['count'] || 0);
                    var ipList = $('#resolved-ips-list');
                    ipList.empty();
                    if (data['ips'] && data['ips'].length > 0) {
                        $.each(data['ips'], function(idx, ip) {
                            ipList.append('<li><code>' + ip + '</code></li>');
                        });
                    } else {
                        ipList.append('<li><em>No IPs resolved yet</em></li>');
                    }
                }
            });
        }
        loadResolvedIps();

        // Load discovered domains
        function loadDiscoveredDomains() {
            ajaxGet("/api/customconfig/service/getDiscoveredDomains", {}, function(data, status) {
                if (data) {
                    $('#discovered-count').text(data['count'] || 0);
                    var domainList = $('#discovered-domains-list');
                    domainList.empty();
                    if (data['domains'] && data['domains'].length > 0) {
                        $.each(data['domains'], function(idx, domain) {
                            domainList.append('<li><code>' + domain + '</code></li>');
                        });
                    } else {
                        domainList.append('<li><em>No domains discovered yet. Domains are learned from DNS queries matching your wildcard patterns.</em></li>');
                    }
                }
            });
        }
        loadDiscoveredDomains();

        $("#saveVpnbypassBtn").click(function(){
            // Get gateway values from our custom dropdowns
            var gatewayVal = $('select[id="vpnbypass.gateway"]').val();
            var gateway6Val = $('select[id="vpnbypass.gateway6"]').val();

            // Save form first
            saveFormToEndpoint("/api/customconfig/settings/setVpnbypass", 'frm_vpnbypass', function(){
                // Then save gateway values separately via direct API call
                var gatewayData = {
                    'vpnbypass': {
                        'gateway': gatewayVal,
                        'gateway6': gateway6Val
                    }
                };
                ajaxCall("/api/customconfig/settings/setVpnbypass", gatewayData, function(data, status) {
                    $("#applyVpnbypassBtn").show();
                });
            });
        });

        $("#applyVpnbypassBtn").click(function(){
            $("#applyVpnbypassBtn").attr("disabled", true);
            ajaxCall("/api/customconfig/service/reconfigure", {}, function(data,status){
                $("#applyVpnbypassBtn").attr("disabled", false);
                $("#applyVpnbypassBtn").hide();
                ajaxCall("/api/customconfig/service/updateVpnbypass", {}, function(data,status){
                    loadResolvedIps();
                    loadDiscoveredDomains();
                    if (data['response']) {
                        BootstrapDialog.show({
                            type: BootstrapDialog.TYPE_INFO,
                            title: "VPN Bypass Update",
                            message: data['response'],
                            buttons: [{
                                label: 'Close',
                                action: function(dialog){ dialog.close(); }
                            }]
                        });
                    }
                });
            });
        });

        $("#updateNowBtn").click(function(){
            $("#updateNowBtn").attr("disabled", true);
            // Run configure first (repopulates discovered domains, flushes cache)
            // then run update (resolves all domains to IPs)
            ajaxCall("/api/customconfig/service/reconfigure", {}, function(data,status){
                ajaxCall("/api/customconfig/service/updateVpnbypass", {}, function(data,status){
                    $("#updateNowBtn").attr("disabled", false);
                    loadResolvedIps();
                    loadDiscoveredDomains();
                    if (data['response']) {
                        BootstrapDialog.show({
                            type: BootstrapDialog.TYPE_INFO,
                            title: "VPN Bypass Update",
                            message: data['response'],
                            buttons: [{
                                label: 'Close',
                                action: function(dialog){ dialog.close(); }
                            }]
                        });
                    }
                });
            });
        });

        $("#refreshIpsBtn").click(function(){
            loadResolvedIps();
        });

        $("#refreshDiscoveredBtn").click(function(){
            loadDiscoveredDomains();
        });

        $("#clearDiscoveredBtn").click(function(){
            BootstrapDialog.confirm({
                title: 'Clear Discovered Domains',
                message: 'Are you sure you want to clear all discovered domains? They will be re-learned from DNS queries.',
                type: BootstrapDialog.TYPE_WARNING,
                btnOKLabel: 'Clear',
                btnOKClass: 'btn-danger',
                callback: function(result) {
                    if (result) {
                        ajaxCall("/api/customconfig/service/clearDiscovered", {}, function(data, status) {
                            loadDiscoveredDomains();
                        });
                    }
                }
            });
        });

        $("#addDomainBtn").click(function(){
            var domain = $("#addDomainInput").val().trim();
            if (domain) {
                ajaxCall("/api/customconfig/service/addDiscoveredDomain", {domain: domain}, function(data, status) {
                    if (data['result'] === 'ok') {
                        $("#addDomainInput").val('');
                        loadDiscoveredDomains();
                        loadResolvedIps();
                        if (data['response']) {
                            BootstrapDialog.show({
                                type: BootstrapDialog.TYPE_SUCCESS,
                                title: "Domain Added",
                                message: data['response'],
                                buttons: [{
                                    label: 'Close',
                                    action: function(dialog){ dialog.close(); }
                                }]
                            });
                        }
                    } else {
                        BootstrapDialog.show({
                            type: BootstrapDialog.TYPE_DANGER,
                            title: "Error",
                            message: data['message'] || 'Failed to add domain',
                            buttons: [{
                                label: 'Close',
                                action: function(dialog){ dialog.close(); }
                            }]
                        });
                    }
                });
            }
        });

        $("#addDomainInput").keypress(function(e) {
            if (e.which === 13) {
                e.preventDefault();
                $("#addDomainBtn").click();
            }
        });

        // DNS Sniffer controls
        function loadSnifferStatus() {
            ajaxGet("/api/customconfig/service/getSnifferStatus", {}, function(data, status) {
                if (data) {
                    if (data['running']) {
                        $('#sniffer-status').html('<span class="label label-success">Running</span> (PID: ' + data['pid'] + ')');
                        $('#startSnifferBtn').hide();
                        $('#stopSnifferBtn').show();
                    } else {
                        $('#sniffer-status').html('<span class="label label-danger">Stopped</span>');
                        $('#startSnifferBtn').show();
                        $('#stopSnifferBtn').hide();
                    }
                }
            });
        }
        loadSnifferStatus();

        $("#startSnifferBtn").click(function(){
            $(this).attr("disabled", true);
            ajaxCall("/api/customconfig/service/startSniffer", {}, function(data, status) {
                $("#startSnifferBtn").attr("disabled", false);
                loadSnifferStatus();
            });
        });

        $("#stopSnifferBtn").click(function(){
            $(this).attr("disabled", true);
            ajaxCall("/api/customconfig/service/stopSniffer", {}, function(data, status) {
                $("#stopSnifferBtn").attr("disabled", false);
                loadSnifferStatus();
            });
        });

        $("#refreshSnifferBtn").click(function(){
            loadSnifferStatus();
        });
    });
</script>

<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <div class="col-sm-12">
                <div class="pull-right">
                    <button class="btn btn-primary" id="saveVpnbypassBtn">
                        <i class="fa fa-save fa-fw"></i> {{ lang._('Save') }}
                    </button>
                    <button class="btn btn-primary" id="applyVpnbypassBtn" style="display:none;">
                        <i class="fa fa-check fa-fw"></i> {{ lang._('Apply') }}
                    </button>
                    <button class="btn btn-default" id="updateNowBtn">
                        <i class="fa fa-refresh fa-fw"></i> {{ lang._('Update Now') }}
                    </button>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="content-box">
    {{ partial("layout_partials/base_form",['fields':formVpnbypass,'id':'frm_vpnbypass'])}}

    <!-- Gateway dropdowns - added after form since they need dynamic population -->
    <div class="table-responsive">
        <table class="table table-striped table-condensed">
            <tbody>
                <tr>
                    <td style="width: 22%"><div class="control-label">
                        <i class="fa fa-info-circle text-muted" data-toggle="tooltip" title="Gateway to use for bypassed IPv4 traffic"></i>
                        <b>IPv4 Gateway</b>
                    </div></td>
                    <td style="width: 78%">
                        <select id="vpnbypass.gateway" class="selectpicker" data-size="10" data-live-search="true" data-width="334px">
                            <option value="">Loading...</option>
                        </select>
                    </td>
                </tr>
                <tr>
                    <td><div class="control-label">
                        <i class="fa fa-info-circle text-muted" data-toggle="tooltip" title="Gateway to use for bypassed IPv6 traffic"></i>
                        <b>IPv6 Gateway</b>
                    </div></td>
                    <td>
                        <select id="vpnbypass.gateway6" class="selectpicker" data-size="10" data-live-search="true" data-width="334px">
                            <option value="">Loading...</option>
                        </select>
                    </td>
                </tr>
            </tbody>
        </table>
    </div>
</div>

<!-- DNS Sniffer Status -->
<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <h3>DNS Sniffer
                <span id="sniffer-status"><span class="label label-default">Loading...</span></span>
                <button class="btn btn-xs btn-default" id="refreshSnifferBtn" title="Refresh status">
                    <i class="fa fa-refresh"></i>
                </button>
                <button class="btn btn-xs btn-success" id="startSnifferBtn" style="display:none;">
                    <i class="fa fa-play"></i> Start
                </button>
                <button class="btn btn-xs btn-danger" id="stopSnifferBtn" style="display:none;">
                    <i class="fa fa-stop"></i> Stop
                </button>
            </h3>
            <p class="text-muted">
                The DNS sniffer watches for DNS queries matching your wildcard patterns and automatically adds discovered subdomains and their IPs to the bypass list.
            </p>
        </div>
    </div>
</div>

<!-- Discovered Domains Section -->
<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <h3>Discovered Domains <span class="badge" id="discovered-count">0</span>
                <button class="btn btn-xs btn-default" id="refreshDiscoveredBtn" title="Refresh list">
                    <i class="fa fa-refresh"></i>
                </button>
                <button class="btn btn-xs btn-danger" id="clearDiscoveredBtn" title="Clear all">
                    <i class="fa fa-trash"></i>
                </button>
            </h3>
            <p class="text-muted">Subdomains discovered from DNS queries matching your wildcard patterns. These are automatically resolved on each update.</p>

            <!-- Add domain manually -->
            <div class="input-group" style="max-width: 400px; margin-bottom: 10px;">
                <input type="text" class="form-control" id="addDomainInput" placeholder="Add domain manually (e.g., cards.discover.com)">
                <span class="input-group-btn">
                    <button class="btn btn-default" type="button" id="addDomainBtn">
                        <i class="fa fa-plus"></i> Add
                    </button>
                </span>
            </div>

            <ul id="discovered-domains-list" style="max-height: 200px; overflow-y: auto; column-count: 2; -webkit-column-count: 2; -moz-column-count: 2;">
                <li><em>Loading...</em></li>
            </ul>
        </div>
    </div>
</div>

<!-- Resolved IPs Section -->
<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <h3>Resolved IP Addresses <span class="badge" id="ip-count">0</span>
                <button class="btn btn-xs btn-default" id="refreshIpsBtn" title="Refresh list">
                    <i class="fa fa-refresh"></i>
                </button>
            </h3>
            <p class="text-muted">These IPs are currently in the PF table and will bypass VPN:</p>
            <ul id="resolved-ips-list" style="max-height: 300px; overflow-y: auto; column-count: 3; -webkit-column-count: 3; -moz-column-count: 3;">
                <li><em>Loading...</em></li>
            </ul>
        </div>
    </div>
</div>

<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <p><strong>How it works:</strong></p>
            <ul>
                <li>Enter wildcard domains (e.g., <code>*.discover.com</code>) in the Bypass Domains field - one per line, or separated by spaces/tabs</li>
                <li>Common subdomains (www, api, login, etc.) are automatically resolved</li>
                <li>The DNS Sniffer watches for queries matching your wildcards and adds discovered subdomains automatically</li>
                <li>All configured and discovered domains are resolved to IP addresses on each update</li>
                <li>Traffic to those IPs is routed through the specified gateway instead of VPN</li>
            </ul>
        </div>
    </div>
</div>
