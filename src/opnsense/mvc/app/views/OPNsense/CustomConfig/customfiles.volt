{#
 # Custom Config - Custom Files
 #}

<script>
    $(document).ready(function() {
        // Files grid
        $("#grid-files").UIBootgrid({
            search:'/api/customconfig/settings/searchFile',
            get:'/api/customconfig/settings/getFile/',
            set:'/api/customconfig/settings/setFile/',
            add:'/api/customconfig/settings/addFile/',
            del:'/api/customconfig/settings/delFile/'
        });

        $("#applyFilesBtn").click(function(){
            $("#applyFilesBtn").attr("disabled", true);
            ajaxCall("/api/customconfig/service/reconfigure", {}, function(data,status){
                $("#applyFilesBtn").attr("disabled", false);
                BootstrapDialog.show({
                    type: BootstrapDialog.TYPE_INFO,
                    title: "Custom Files",
                    message: "Configuration applied successfully",
                    buttons: [{
                        label: 'Close',
                        action: function(dialog){ dialog.close(); }
                    }]
                });
            });
        });
    });
</script>

<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <div class="col-sm-12">
                <div class="pull-right">
                    <button class="btn btn-primary" id="applyFilesBtn">
                        <i class="fa fa-check fa-fw"></i> {{ lang._('Apply Changes') }}
                    </button>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <table id="grid-files" class="table table-condensed table-hover table-striped" data-editDialog="dialogFile">
                <thead>
                    <tr>
                        <th data-column-id="enabled" data-formatter="rowtoggle" data-sortable="false" data-width="6em">{{ lang._('Enabled') }}</th>
                        <th data-column-id="name" data-type="string">{{ lang._('Name') }}</th>
                        <th data-column-id="filepath" data-type="string">{{ lang._('File Path') }}</th>
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

<div class="content-box">
    <div class="content-box-main">
        <div class="table-responsive">
            <p><strong>Notes:</strong></p>
            <ul>
                <li>Custom files are written to the specified paths when you click Apply</li>
                <li>If a reload command is specified, it will run after the file is written</li>
                <li>File content is stored in config.xml and backed up with normal backups</li>
            </ul>
        </div>
    </div>
</div>

{{ partial("layout_partials/base_dialog",['fields':formDialogFile,'id':'dialogFile','label':lang._('Edit Custom File')])}}
