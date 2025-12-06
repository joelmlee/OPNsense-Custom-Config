{#
 # Custom Config - Monit Process Monitor
 #}

<script>
    $(document).ready(function() {
        // Load general settings
        mapDataToFormUI({'frm_monitprocess':"/api/customconfig/settings/getMonitprocess"}).done(function(){
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        // Process grid
        $("#grid-processes").UIBootgrid({
            search:'/api/customconfig/settings/searchProcess',
            get:'/api/customconfig/settings/getProcess/',
            set:'/api/customconfig/settings/setProcess/',
            add:'/api/customconfig/settings/addProcess/',
            del:'/api/customconfig/settings/delProcess/'
        });

        $("#saveMonitBtn").click(function(){
            saveFormToEndpoint("/api/customconfig/settings/setMonitprocess", 'frm_monitprocess', function(){
                $("#applyMonitBtn").show();
            });
        });

        $("#applyMonitBtn").click(function(){
            $("#applyMonitBtn").attr("disabled", true);
            ajaxCall("/api/customconfig/service/reconfigure", {}, function(data,status){
                $("#applyMonitBtn").attr("disabled", false);
                $("#applyMonitBtn").hide();
            });
        });
    });
</script>

<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <div class="col-sm-12">
                <div class="pull-right">
                    <button class="btn btn-primary" id="saveMonitBtn">
                        <i class="fa fa-save fa-fw"></i> {{ lang._('Save') }}
                    </button>
                    <button class="btn btn-primary" id="applyMonitBtn" style="display:none;">
                        <i class="fa fa-check fa-fw"></i> {{ lang._('Apply') }}
                    </button>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="content-box">
    {{ partial("layout_partials/base_form",['fields':formMonitprocess,'id':'frm_monitprocess'])}}
</div>

<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <h3>Process Monitors</h3>
            <table id="grid-processes" class="table table-condensed table-hover table-striped" data-editDialog="dialogProcess">
                <thead>
                    <tr>
                        <th data-column-id="name" data-type="string">{{ lang._('Name') }}</th>
                        <th data-column-id="matchpattern" data-type="string">{{ lang._('Match Pattern') }}</th>
                        <th data-column-id="startcmd" data-type="string">{{ lang._('Start Command') }}</th>
                        <th data-column-id="commands" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
                        <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                    </tr>
                </thead>
                <tbody>
                </tbody>
                <tfoot>
                    <tr>
                        <td></td>
                        <td></td>
                        <td></td>
                        <td></td>
                    </tr>
                </tfoot>
            </table>
        </div>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':formDialogProcess,'id':'dialogProcess','label':lang._('Edit Process Monitor')])}}
