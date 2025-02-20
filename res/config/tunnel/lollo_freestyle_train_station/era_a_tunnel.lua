function data()
    return {
      name = _('EraATunnel'),
      carriers = { 'RAIL', 'ROAD' },
      portals = {
        { 'lollo_freestyle_train_station/tunnel/era_a_tunnel.mdl' },
        -- { 'railroad/tunnel_old.mdl' },
        -- { 'railroad/tunnel_double_old.mdl' },
        -- { 'railroad/tunnel_large_start.mdl', 'railroad/tunnel_large_rep.mdl', 'railroad/tunnel_large_end.mdl' },
      },
      cost = 100.0, -- 1200
      categories = { 'misc' },
    }
end
