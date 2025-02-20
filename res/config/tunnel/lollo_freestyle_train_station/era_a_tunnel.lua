function data()
    return {
      name = _('EraATunnel'),
      carriers = { 'RAIL', 'ROAD' },
      portals = {
        { 'lollo_freestyle_train_station/tunnel/era_a_single_tunnel.mdl' },
        { 'lollo_freestyle_train_station/tunnel/era_a_double_tunnel.mdl' },
        { 'lollo_freestyle_train_station/tunnel/era_a_tunnel_start.mdl', 'lollo_freestyle_train_station/tunnel/era_a_tunnel_rep.mdl', 'lollo_freestyle_train_station/tunnel/era_a_tunnel_end.mdl' },
        -- { 'railroad/tunnel_old.mdl' },
        -- { 'railroad/tunnel_double_old.mdl' },
        -- { 'railroad/tunnel_large_start.mdl', 'railroad/tunnel_large_rep.mdl', 'railroad/tunnel_large_end.mdl' },
      },
      cost = 800.0,
      categories = { 'misc' },
    }
end
