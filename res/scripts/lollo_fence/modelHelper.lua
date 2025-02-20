local arrayUtils = require('lollo_freestyle_train_station.arrayUtils')
local constants = require('lollo_freestyle_train_station.constants')


local _platformHeightsSorted = {}
for _, plh in pairs(constants.platformHeights) do
    _platformHeightsSorted[#_platformHeightsSorted+1] = plh
end
arrayUtils.sort(_platformHeightsSorted, 'aboveRail', true)
local _getZShiftDefaultIndex = function()
    local index_base0 = 0
    for _, plh in pairs(_platformHeightsSorted) do
        if plh.aboveGround == constants.defaultPlatformHeight then return index_base0 end
        index_base0 = index_base0 + 1
    end
    return 0
end

local privateValues = {
    maxLength = 200,
    yShiftMaxIndex = 24,
    yShiftFineMaxIndex = 5,
    zDeltaMaxIndex = 64,
    zRotationMaxIndex = 64,
}
privateValues.defaults = {
    -- lolloFenceAssets_buildOnFrozenEdges = 0,
    lolloFenceAssets_doTerrain = 1,
    lolloFenceAssets_isWallBehindThick = 0,
    -- lolloFenceAssets_isWallTall = 0,
    lolloFenceAssets_length = 9,
    lolloFenceAssets_model = 15,
    lolloFenceAssets_wallEraPrefix = 1,
    lolloFenceAssets_wallBehindModel = 0,
    lolloFenceAssets_wallBehindInTunnels = 0,
    lolloFenceAssets_wallBehindOnBridges = 0,
    lolloFenceAssets_yShift = privateValues.yShiftMaxIndex + 5,
    lolloFenceAssets_yShiftFine = privateValues.yShiftFineMaxIndex,
    lolloFenceAssets_zDelta = privateValues.zDeltaMaxIndex,
    lolloFenceAssets_zRotation = privateValues.zRotationMaxIndex,
    lolloFenceAssets_zShift = _getZShiftDefaultIndex(),
}
local privateFuncs = {
    getLengthValues = function()
        local results = {}
        for i = 1, privateValues.maxLength, 1 do
            results[#results+1] = tostring(i)
        end
        return results
    end,
    getYShiftActualValues = function()
        local results = {}
        for i = -privateValues.yShiftMaxIndex, privateValues.yShiftMaxIndex, 1 do
            results[#results+1] = i / 2
        end
        return results
    end,
    getYShiftDisplayValues = function()
        local results = {}
        for i = -privateValues.yShiftMaxIndex, privateValues.yShiftMaxIndex, 1 do
            results[#results+1] = ("%.3g"):format(i / 2)
        end
        return results
    end,
    getYShiftFineActualValues = function()
        local results = {}
        for i = -privateValues.yShiftFineMaxIndex, privateValues.yShiftFineMaxIndex, 1 do
            results[#results+1] = i * 0.1
        end
        return results
    end,
    getYShiftFineDisplayValues = function()
        local results = {}
        for i = -privateValues.yShiftFineMaxIndex, privateValues.yShiftFineMaxIndex, 1 do
            results[#results+1] = ("%.3g"):format(i * 0.1)
        end
        return results
    end,
    getZDeltaActualValues = function()
        local results = {}
        for i = -privateValues.zDeltaMaxIndex, privateValues.zDeltaMaxIndex, 1 do
            results[#results+1] = i / privateValues.zDeltaMaxIndex
        end
        return results
    end,
    getZDeltaDisplayValues = function()
        local results = {}
        for i = -privateValues.zDeltaMaxIndex, privateValues.zDeltaMaxIndex, 1 do
            results[#results+1] = ("%.3g %%"):format(i * 100 / privateValues.zDeltaMaxIndex)
        end
        return results
    end,
    getZRotationActualValues = function()
        local results = {}
        for i = -privateValues.zRotationMaxIndex, privateValues.zRotationMaxIndex, 1 do
            results[#results+1] = tostring(i * math.pi / 2 / privateValues.zRotationMaxIndex)
        end
        return results
    end,
    getZRotationDisplayValues = function()
        local results = {}
        for i = -privateValues.zRotationMaxIndex, privateValues.zRotationMaxIndex, 1 do
            results[#results+1] = ("%.2g °"):format(i / privateValues.zRotationMaxIndex * 90)
        end
        return results
    end,
    getZShiftActualValues = function()
        local results = {}
        for _, plh in pairs(_platformHeightsSorted) do
            results[#results+1] = plh.aboveGround - constants.defaultPlatformHeight
        end
        return results
    end,
    getZShiftDisplayValues = function()
        local results = {}
        for _, plh in pairs(_platformHeightsSorted) do
            results[#results+1] = ("%.3g m"):format(plh.aboveRail)
        end
        return results
    end,
    getModels = function(isTunnel)
        local results = {}
        local add = function(modelFileName, iconFileName, name)
            results[#results+1] = {
                fileName = modelFileName,
                icon = iconFileName,
                -- id = id,
                name = name
            }
        end
        if isTunnel then
            add(nil, 'ui/lollo_freestyle_train_station/none.tga', _('NoWallName'))
            add('lollo_freestyle_train_station/platformWalls/arched/franz_glass_copper_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallArchedFranzGlassCopper.tga', _("WallArchedFranzGlassCopperName"))
            add('lollo_freestyle_train_station/platformWalls/arched/franz_glass_metal_001_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallArchedFranzGlassMetal001.tga', _("WallArchedFranzGlassMetal001Name"))
            add('lollo_freestyle_train_station/platformWalls/arched/franz_glass_metal_002_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallArchedFranzGlassMetal002.tga', _("WallArchedFranzGlassMetal002Name"))
            add('lollo_freestyle_train_station/platformWalls/arched/tiles_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallTiled.tga', _("WallTiledName"))
            add('lollo_freestyle_train_station/platformWalls/arched/copper_large_rivets_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallIronGlassCopper.tga', _("WallIronGlassCopperName"))
            add('lollo_freestyle_train_station/platformWalls/arched/iron_large_rivets_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallIron.tga', _("WallIronName"))
            add('lollo_freestyle_train_station/platformWalls/arched/tunnely_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallTunnely.tga', _('WallTunnelyName'))
            add('lollo_freestyle_train_station/platformWalls/arched/tunnely_light_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallTunnelyLight.tga', _('WallTunnelyLightName'))
            add('lollo_freestyle_train_station/platformWalls/arched/tunnely_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallFenceWood.tga', _("WallFenceWoodName"))
            add('lollo_freestyle_train_station/platformWalls/arched/tiles_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallFenceBricksStone.tga', _("WallFenceBricksStoneName"))
            add('lollo_freestyle_train_station/platformWalls/arched/tiles_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallFenceMattoni.tga', _("WallFenceMattoniName"))
            add('lollo_freestyle_train_station/platformWalls/arched/tiles_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallArcoMattoni.tga', _("WallArcoMattoniName"))
            add('lollo_freestyle_train_station/platformWalls/arched/bricks_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallBricks.tga', _('WallBricksName'))
            add('lollo_freestyle_train_station/platformWalls/arched/tunnely_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallStaccionataFs.tga', _("WallStaccionataFsName"))
            add('lollo_freestyle_train_station/platformWalls/arched/tiles_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallStaccionataFsTall.tga', _("WallStaccionataFsTallName"))
            add('lollo_freestyle_train_station/platformWalls/arched/concrete_plain_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallConcretePlain.tga', _("WallConcretePlainName"))
            add('lollo_freestyle_train_station/platformWalls/arched/tiled_large_stripes_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallTiledWLargeStripes.tga', _("WallTiledWLargeStripesName"))
            add('lollo_freestyle_train_station/platformWalls/arched/concrete_modern_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallConcreteModern.tga', _("WallConcreteModernName"))
            add('lollo_freestyle_train_station/platformWalls/arched/metal_glass_wall_tunnel_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallMetalGlass.tga', _("WallMetalGlassName"))
        else
            add(nil, 'ui/lollo_freestyle_train_station/none.tga', _('NoWallName'))
            add('lollo_freestyle_train_station/platformWalls/arched/franz_glass_copper_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallArchedFranzGlassCopper.tga', _("WallArchedFranzGlassCopperName"))
            add('lollo_freestyle_train_station/platformWalls/arched/franz_glass_metal_001_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallArchedFranzGlassMetal001.tga', _("WallArchedFranzGlassMetal001Name"))
            add('lollo_freestyle_train_station/platformWalls/arched/franz_glass_metal_002_2_5m.mdl', 'ui/lollo_freestyle_train_station/wallArchedFranzGlassMetal002.tga', _("WallArchedFranzGlassMetal002Name"))
            add('lollo_freestyle_train_station/platformWalls/tiled/platformWall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallTiled.tga', _("WallTiledName"))
            add('lollo_freestyle_train_station/platformWalls/iron_glass_copper/platformWall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallIronGlassCopper.tga', _("WallIronGlassCopperName"))
            add('lollo_freestyle_train_station/platformWalls/iron/wall_5m.mdl', 'ui/lollo_freestyle_train_station/wallIron.tga', _("WallIronName"))
            add('lollo_freestyle_train_station/platformWalls/tunnely/wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallTunnely.tga', _('WallTunnelyName'))
            add('lollo_freestyle_train_station/platformWalls/tunnely_light/wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallTunnelyLight.tga', _('WallTunnelyLightName'))
            add('lollo_freestyle_train_station/platformWalls/fence_wood/fence_5m.mdl', 'ui/lollo_freestyle_train_station/wallFenceWood.tga', _("WallFenceWoodName"))
            add('lollo_freestyle_train_station/platformWalls/fence_bricks_stone/fence_5m.mdl', 'ui/lollo_freestyle_train_station/wallFenceBricksStone.tga', _("WallFenceBricksStoneName"))
            add('lollo_freestyle_train_station/platformWalls/fence_mattoni/square_fence_5m.mdl', 'ui/lollo_freestyle_train_station/wallFenceMattoni.tga', _("WallFenceMattoniName"))
            add('lollo_freestyle_train_station/platformWalls/arco_mattoni/wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallArcoMattoni.tga', _("WallArcoMattoniName"))
            add('lollo_freestyle_train_station/platformWalls/bricks/platformWall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallBricks.tga', _('WallBricksName'))
            add('lollo_freestyle_train_station/platformWalls/staccionata_fs/modelled_wall_5m.mdl', 'ui/lollo_freestyle_train_station/wallStaccionataFs.tga', _("WallStaccionataFsName"))
            add('lollo_freestyle_train_station/platformWalls/staccionata_fs_tall/modelled_wall_5m.mdl', 'ui/lollo_freestyle_train_station/wallStaccionataFsTall.tga', _("WallStaccionataFsTallName"))
            add('lollo_freestyle_train_station/platformWalls/concrete_plain/platformWall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallConcretePlain.tga', _("WallConcretePlainName"))
            add('lollo_freestyle_train_station/platformWalls/tiled_large_stripes/wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallTiledWLargeStripes.tga', _("WallTiledWLargeStripesName"))
            add('lollo_freestyle_train_station/platformWalls/concrete_modern/wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallConcreteModern.tga', _("WallConcreteModernName"))
            add('lollo_freestyle_train_station/platformWalls/metal_glass/platformWall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallMetalGlass.tga', _("WallMetalGlassName"))
        end
        return results
    end,
    getWallBehindModels = function(isWallTall, isWallBehindThick)
        local results = {}
        local add = function(modelFileName, iconFileName, name)
            results[#results+1] = {
                fileName = modelFileName,
                icon = iconFileName,
                -- id = id,
                name = name
            }
        end
        if isWallBehindThick then
            if isWallTall then
                add(nil, 'ui/lollo_freestyle_train_station/none.tga', _('NoWallName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnely.tga', _('WallTunnelyName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_light_wall_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnelyLight.tga', _('WallTunnelyNLightame'))
                add('lollo_freestyle_train_station/platformWalls/behind/brick_wall_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallBricks.tga', _('WallBricksName'))
                add('lollo_freestyle_train_station/platformWalls/behind/concrete_wall_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallConcretePlain.tga', _("WallConcretePlainName"))
            else
                add(nil, 'ui/lollo_freestyle_train_station/none.tga', _('NoWallName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnely.tga', _('WallTunnelyName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_light_wall_low_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnelyLight.tga', _('WallTunnelyLightName'))
                add('lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallBricks.tga', _('WallBricksName'))
                add('lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m_2m_thick.mdl', 'ui/lollo_freestyle_train_station/wallConcretePlain.tga', _("WallConcretePlainName"))
            end
        else
            if isWallTall then
                add(nil, 'ui/lollo_freestyle_train_station/none.tga', _('NoWallName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_5m.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnely.tga', _('WallTunnelyName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_light_wall_5m.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnelyLight.tga', _('WallTunnelyNLightame'))
                add('lollo_freestyle_train_station/platformWalls/behind/brick_wall_5m.mdl', 'ui/lollo_freestyle_train_station/wallBricks.tga', _('WallBricksName'))
                add('lollo_freestyle_train_station/platformWalls/behind/concrete_wall_5m.mdl', 'ui/lollo_freestyle_train_station/wallConcretePlain.tga', _("WallConcretePlainName"))
            else
                add(nil, 'ui/lollo_freestyle_train_station/none.tga', _('NoWallName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnely.tga', _('WallTunnelyName'))
                add('lollo_freestyle_train_station/platformWalls/behind/tunnely_light_wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallBehindTunnelyLight.tga', _('WallTunnelyLightName'))
                add('lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallBricks.tga', _('WallBricksName'))
                add('lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m.mdl', 'ui/lollo_freestyle_train_station/wallConcretePlain.tga', _("WallConcretePlainName"))
            end
        end
        return results
    end,
}

return {
    getModels = function(isTunnel)
        return privateFuncs.getModels(isTunnel)
    end,
    getWallBehindModels = function(isTunnel, isWallBehindThick)
        return privateFuncs.getWallBehindModels(isTunnel, isWallBehindThick)
    end,
    getConParams = function ()
        local models = privateFuncs.getModels()
        local wallBehindModels = privateFuncs.getWallBehindModels()
        return {
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_model,
                key = 'lolloFenceAssets_model',
                name = _('fenceModelName'),
                values = arrayUtils.map(
                    models,
                    function(model)
                        -- return model.name
                        return model.icon
                    end
                ),
                uiType = 'ICON_BUTTON',
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_wallEraPrefix,
                key = 'lolloFenceAssets_wallEraPrefix',
                name = _('wallEraPrefix_0IsNoWall'),
                uiType = 'BUTTON',
                values = {_('NoWall'), 'A', 'B', 'C'},
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_wallBehindModel,
                key = 'lolloFenceAssets_wallBehindModel',
                name = _('wallBehindModel_0IsNoWall'),
                values = arrayUtils.map(
                    wallBehindModels,
                    function(model)
                        -- return model.name
                        return model.icon
                    end
                ),
                uiType = 'ICON_BUTTON',
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_isWallBehindThick,
                key = 'lolloFenceAssets_isWallBehindThick',
                name = _('isWallBehindThick'),
                uiType = 'BUTTON',
                values = {_('NO'), _('YES')},
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_doTerrain,
                key = 'lolloFenceAssets_doTerrain',
                name = _('DoTerrain'),
                uiType = 'BUTTON',
                values = {_('NO'), _('YES'), _('Raise'), _('Lower')}
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_length,
                key = 'lolloFenceAssets_length',
                name = _('Length'),
                uiType = 'SLIDER',
                values = privateFuncs.getLengthValues(),
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_yShift,
                key = 'lolloFenceAssets_yShift',
                name = _('YShift'),
                uiType = 'SLIDER',
                values = privateFuncs.getYShiftDisplayValues(),
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_yShiftFine,
                key = 'lolloFenceAssets_yShiftFine',
                name = _('YShiftFine'),
                uiType = 'SLIDER',
                values = privateFuncs.getYShiftFineDisplayValues(),
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_zRotation,
                key = 'lolloFenceAssets_zRotation',
                name = _('ZRotation'),
                uiType = 'SLIDER',
                values = privateFuncs.getZRotationDisplayValues(),
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_zDelta,
                key = 'lolloFenceAssets_zDelta',
                name = _('ZDelta'),
                uiType = 'SLIDER',
                values = privateFuncs.getZDeltaDisplayValues(),
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_zShift,
                key = 'lolloFenceAssets_zShift',
                name = _('ZShift'),
                uiType = 'BUTTON',
                values = privateFuncs.getZShiftDisplayValues(),
            },
            -- {
            --     defaultIndex = privateValues.defaults.lolloFenceAssets_isWallTall,
            --     key = 'lolloFenceAssets_isWallTall',
            --     name = _('IsWallTall'),
            --     uiType = 'BUTTON',
            --     values = {_('NO'), _('YES')}
            -- },
        }
    end,
    getChangeableParamsMetadata = function()
        local models = privateFuncs.getModels()
        local wallBehindModels = privateFuncs.getWallBehindModels()
        local metadata_sorted = {
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_model,
                key = 'lolloFenceAssets_model',
                name = _('fenceModelName'),
                values = arrayUtils.map(
                    models,
                    function(model)
                        -- return model.name
                        return model.icon
                    end
                ),
                uiType = 'ICON_BUTTON',
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_wallEraPrefix,
                key = 'lolloFenceAssets_wallEraPrefix',
                name = _('wallEraPrefix_0IsNoWall'),
                uiType = 'BUTTON',
                values = {_('NoWall'), 'A', 'B', 'C'},
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_wallBehindModel,
                key = 'lolloFenceAssets_wallBehindModel',
                name = _('wallBehindModel_0IsNoWall'),
                values = arrayUtils.map(
                    wallBehindModels,
                    function(model)
                        -- return model.name
                        return model.icon
                    end
                ),
                uiType = 'ICON_BUTTON',
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_isWallBehindThick,
                key = 'lolloFenceAssets_isWallBehindThick',
                name = _('isWallBehindThick'),
                uiType = 'BUTTON',
                values = {_('NO'), _('YES')},
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_wallBehindOnBridges,
                key = 'lolloFenceAssets_wallBehindOnBridges',
                name = _('wallBehind_isOnBridges'),
                uiType = 'CHECKBOX',
                values = {_('NO'), _('YES')}
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_wallBehindInTunnels,
                key = 'lolloFenceAssets_wallBehindInTunnels',
                name = _('wallBehind_isInTunnels'),
                uiType = 'CHECKBOX',
                values = {_('NO'), _('YES')}
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_doTerrain,
                key = 'lolloFenceAssets_doTerrain',
                name = _('DoTerrain'),
                uiType = 'BUTTON',
                values = {_('NO'), _('YES'), _('Raise'), _('Lower')}
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_yShiftFine,
                key = 'lolloFenceAssets_yShiftFine',
                name = _('YShift'),
                uiType = 'SLIDER',
                values = privateFuncs.getYShiftFineDisplayValues(),
            },
            {
                defaultIndex = privateValues.defaults.lolloFenceAssets_zShift,
                key = 'lolloFenceAssets_zShift',
                name = _('ZShift'),
                uiType = 'BUTTON',
                values = privateFuncs.getZShiftDisplayValues(),
            },
            -- there is no way yet to accurately find out if an edge is frozen without the api:
            -- I often add or remove one metre, unless I rewrite getCentralEdgePositions_OnlyOuterBounds
            -- {
            --     defaultIndex = privateValues.defaults.lolloFenceAssets_buildOnFrozenEdges,
            --     key = 'lolloFenceAssets_buildOnFrozenEdges',
            --     name = _('BuildOnStations'),
            --     uiType = 'CHECKBOX',
            --     values = {_('NO'), _('YES')}
            -- },
        }
        -- add defaultIndex wherever not present
        for _, record in pairs(metadata_sorted) do
            record.defaultIndex = record.defaultIndex or 0
        end
        local metadata_indexed = {}
        for _, record in pairs(metadata_sorted) do
            metadata_indexed[record.key] = record
        end
        -- logger.print('metadata_sorted =') logger.debugPrint(metadata_sorted)
        -- logger.print('metadata_indexed =') logger.debugPrint(metadata_indexed)
        return metadata_sorted, metadata_indexed
    end,
    getUiTypeNumber = function(uiTypeStr)
        if uiTypeStr == 'BUTTON' then return 0
        elseif uiTypeStr == 'SLIDER' then return 1
        elseif uiTypeStr == 'COMBOBOX' then return 2
        elseif uiTypeStr == 'ICON_BUTTON' then return 3 -- double-check this
        elseif uiTypeStr == 'CHECKBOX' then return 4 -- double-check this
        else return 0
        end
    end,
    getYShiftActualValues = function()
        return privateFuncs.getYShiftActualValues()
    end,
    getYShiftFineActualValues = function()
        return privateFuncs.getYShiftFineActualValues()
    end,
    getZDeltaActualValues = function()
        return privateFuncs.getZDeltaActualValues()
    end,
    getZRotationActualValues = function()
        return privateFuncs.getZRotationActualValues()
    end,
    getZShiftActualValues = function()
        return privateFuncs.getZShiftActualValues()
    end,
    getDefaultIndexes = function()
        return privateValues.defaults
    end
    -- getConstants = function()
    --     return privateValues
    -- end,
}
