deploy_host := env_var_or_default("THISTLE_TEA_DEPLOY_HOST", "root@shimarin")
data_dir := "/var/lib/thistle-tea"

deploy-data:
    rsync --archive --verbose --compress --checksum --partial --info=progress2 \
        db/vmangos.sqlite \
        db/dbc.sqlite \
        {{ deploy_host }}:{{ data_dir }}/db/
    rsync --archive --verbose --compress --checksum --partial --info=progress2 \
        maps/ \
        {{ deploy_host }}:{{ data_dir }}/maps/
    ssh {{ deploy_host }} \
        'chown -R thistle-tea:thistle-tea {{ data_dir }}/db {{ data_dir }}/maps'
