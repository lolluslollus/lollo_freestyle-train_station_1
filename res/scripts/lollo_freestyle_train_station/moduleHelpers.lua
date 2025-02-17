local arrayUtils = require('lollo_freestyle_train_station.arrayUtils')
local autoBridgePathsHelper = require('lollo_freestyle_train_station.autoBridgePathsHelper')
local comparisonUtils = require('lollo_freestyle_train_station.comparisonUtils')
local constants = require('lollo_freestyle_train_station.constants')
local logger = require('lollo_freestyle_train_station.logger')
local modulesutil = require 'modulesutil'
local openLiftOpenStairsHelpers = require('lollo_open_lifts_open_stairs_free.openLiftOpenStairsHelpers')
local slotHelpers = require('lollo_freestyle_train_station.slotHelpers')
local stringUtils = require('lollo_freestyle_train_station.stringUtils')
local trackUtils = require('lollo_freestyle_train_station.trackHelpers')
local transfUtils = require('lollo_freestyle_train_station.transfUtils')
local transfUtilsUG = require 'transf'


local privateConstants = {
    cargoShelves = {
        -- setting this to 2 gets a negligible performance boost and uglier joints,
        -- particularly on slopes and bends
        bracketStep = 1,
        pillarPeriod = 5,
    },
    deco = {
        -- LOLLO NOTE setting this to 2 gets a negligible performance boost and uglier joints,
        -- particularly on slopes and bends
        ceilingStep = 1,
        numberSignPeriod = constants.maxPassengerWaitingAreaEdgeLength * 4,
        pillarPeriod = 4, -- this should be a submultiple of numberSignPeriod
    },
    lifts = {
        -- bridgeHeights = { 5, 10, 15, 20, 25, 30, 35, 40 } -- too little, stations get buried
        bridgeHeights = { 2.5, 7.5, 12.5, 17.5, 22.5, 27.5, 32.5, 37.5, 42.5 }
        -- bridgeHeights = { 6.5, 11.5, 16.5, 21.5, 26.5, 31.5, 36.5, 41.5 }
    },
    slopedAreasOLD = {
        -- hunchLengthRatioToClaimBend = 0.01, -- must be positive
        hunchToClaimBend = 0.2, -- must be positive
        innerDegrees = {
            inner = 1,
            neutral = 0,
            outer = -1
        },
    }
}

local privateFuncs = {
    ---@param variant integer
    ---@return number
    getFromVariant_0_or_1 = function(variant)
        return math.abs(math.fmod(variant, 2))
    end,
    ---@param variant integer
    ---@return number
    getFromVariant_0_to_1 = function(variant, nSteps)
        local _nSteps = math.ceil(nSteps)
        return math.abs(math.fmod(variant, _nSteps) / (nSteps - 1))
    end,
    ---@param variant integer
    ---@return number, number, number
    getFromVariant_AxialAreaTilt = function(variant)
        local tilt = -variant * 0.025
        local _maxRadAbs = 0.36
        if tilt > _maxRadAbs then tilt = _maxRadAbs elseif tilt < -_maxRadAbs then tilt = -_maxRadAbs end
        -- logger.print('getFromVariant_AxialAreaTilt returning', tilt, -_maxRadAbs, _maxRadAbs)
        return tilt, -_maxRadAbs, _maxRadAbs
    end,
    ---@param variant integer
    ---@return number, number, number
    getFromVariant_BridgeTilt = function(variant)
        local tilt = variant * 0.0125
        local _maxRadAbs = 0.36
        if tilt > _maxRadAbs then tilt = _maxRadAbs elseif tilt < -_maxRadAbs then tilt = -_maxRadAbs end
        -- logger.print('getFromVariant_BridgeTilt returning', tilt, -_maxRadAbs, _maxRadAbs)
        -- LOLLO TODO in a future major release, return -tilt instead of tilt
        return tilt, -_maxRadAbs, _maxRadAbs
    end,
    ---@param variant integer
    ---@return number, number, number
    getFromVariant_FlatAreaHeight = function(variant, isFlush)
        local zShift = variant * 0.1 + (isFlush and 0 or constants.platformSideBitsZ)
        local _maxValueAbs = 1.2
        if zShift > _maxValueAbs then zShift = _maxValueAbs elseif zShift < -_maxValueAbs then zShift = -_maxValueAbs end
        -- logger.print('_getFromVariant_FlatAreaHeight returning', zShift, -_maxValueAbs, _maxValueAbs)
        return zShift, -_maxValueAbs, _maxValueAbs
    end,
    ---@param variant integer
    ---@return integer, integer, integer
    getFromVariant_LiftHeight = function(variant)
        -- LOLLO TODO in a future major release, return 10 instead of -10, 5 instead of -5 etc
        local deltaZ = 0
        if variant <= -2 then
            deltaZ = -10
        elseif variant <= -1 then
            deltaZ = -5
        elseif variant >= 2 then
            deltaZ = 10
        elseif variant >= 1 then
            deltaZ = 5
        end
        -- logger.print('getFromVariant_LiftHeight returning', deltaZ, -10, 10)
        return deltaZ, -10, 10
    end,
    ---get era prefix of current terminal bit and overwrite it with the era module if present
    ---@param params table
    ---@param nTerminal integer
    ---@param terminalData table
    ---@param nTrackEdge integer
    ---@return eraPrefix
    getEraPrefix = function(params, nTerminal, terminalData, nTrackEdge)
        local _modules = params.modules
        local cpl = terminalData.centrePlatformsRelative[nTrackEdge] or terminalData.centrePlatformsRelative[1]
        local result = cpl.era or constants.eras.era_c.prefix
        if _modules then
            if _modules[slotHelpers.mangleId(nTerminal, 0, constants.idBases.platformEraASlotId)] then
                result = constants.eras.era_a.prefix
            elseif _modules[slotHelpers.mangleId(nTerminal, 0, constants.idBases.platformEraBSlotId)] then
                result = constants.eras.era_b.prefix
            elseif _modules[slotHelpers.mangleId(nTerminal, 0, constants.idBases.platformEraCSlotId)] then
                result = constants.eras.era_c.prefix
            end
        end

        return result
    end,
    getGroundFacesFillKey_cargo = function(result, nTerminal, eraPrefix)
        local groundFacesFillKey = constants[eraPrefix .. 'groundFacesFillKey']
        if result.platformStyles[nTerminal] == constants.cargoPlatformStyles.cargo_earth.moduleFileName then
            groundFacesFillKey = constants.earth_groundFacesFillKey
        elseif result.platformStyles[nTerminal] == constants.cargoPlatformStyles.cargo_gravel.moduleFileName then
            groundFacesFillKey = constants.gravel_groundFacesFillKey
        end
        -- if result.laneZs[nTerminal] == constants.platformHeights._0cm.aboveGround then groundFacesFillKey = constants.gravel_groundFacesFillKey end

        return groundFacesFillKey
    end,
    getGroundFacesFillKey_passengers = function(eraPrefix)
        return constants[eraPrefix .. 'groundFacesFillKey']
    end,
    getIsEndFillerEvery3 = function(nTrackEdge)
        -- this is for platform roofs and outside extensions, which have a slot every 3 track edge counts.
        -- to fill the last, if it is 4, 7, etc, we add an extra slot: this slot has a special behaviour,
        -- ie it does not draw on the adjacent track edges
        return math.fmod(nTrackEdge, 3) == 1
    end,
    getIsTerrainFlush = function (result, nTerminal)
        return (
            result.platformStyles[nTerminal] == constants.cargoPlatformStyles.cargo_earth.moduleFileName
            or result.platformStyles[nTerminal] == constants.cargoPlatformStyles.cargo_gravel.moduleFileName
            or result.laneZs[nTerminal] == constants.platformHeights._0cm.aboveGround
        )
    end,
    getPlatformObjectTransf_AlwaysVertical = function(posTanX2)
        -- logger.print('getPlatformObjectTransf_AlwaysVertical starting, posTanX2 =') logger.debugPrint(posTanX2)
        local pos1 = posTanX2[1][1]
        local pos2 = posTanX2[2][1]

        local sinZ = pos2[2] - pos1[2]
        local cosZ = pos2[1] - pos1[1]
        local _lengthZ = math.sqrt(sinZ * sinZ + cosZ * cosZ)
        sinZ, cosZ = sinZ / _lengthZ, cosZ / _lengthZ

        return {
            cosZ, sinZ, 0, 0,
            -sinZ, cosZ, 0, 0,
            0, 0, 1, 0,
            (pos1[1] + pos2[1]) * 0.5, (pos1[2] + pos2[2]) * 0.5, (pos1[3] + pos2[3]) * 0.5, 1
        }
    end,
    getPlatformObjectTransf_WithYRotationOLD = function(posTanX2) --, angleYFactor)
        -- logger.print('_getUnderpassTransfWithYRotation starting, posTanX2 =') logger.debugPrint(posTanX2)
        local pos1 = posTanX2[1][1]
        local pos2 = posTanX2[2][1]

        local angleZ = math.atan2(pos2[2] - pos1[2], pos2[1] - pos1[1])
        local transfZ = transfUtilsUG.rotZTransl(
            angleZ,
            {
                x = (pos1[1] + pos2[1]) * 0.5,
                y = (pos1[2] + pos2[2]) * 0.5,
                z = (pos1[3] + pos2[3]) * 0.5,
            }
        )

        local angleY = math.atan2(
            (pos2[3] - pos1[3]),
            transfUtils.getVectorLength(
                {
                    pos2[1] - pos1[1],
                    pos2[2] - pos1[2],
                    0
                }
            ) -- * (angleYFactor or 1)
        )

        local transfY = transfUtilsUG.rotY(-angleY)

        return transfUtilsUG.mul(transfZ, transfY)
        -- return transfUtilsUG.mul(transfY, transfZ) -- NO!
    end,
    getPlatformObjectTransf_WithYRotation = function(posTanX2) --, angleYFactor)
        -- logger.print('_getUnderpassTransfWithYRotation starting, posTanX2 =') logger.debugPrint(posTanX2)
        local pos1 = posTanX2[1][1]
        local pos2 = posTanX2[2][1]

        local sinZ = pos2[2] - pos1[2]
        local cosZ = pos2[1] - pos1[1]
        local _lengthZ = math.sqrt(sinZ * sinZ + cosZ * cosZ)
        sinZ, cosZ = sinZ / _lengthZ, cosZ / _lengthZ

        -- local transfZ = {
        --     cosZ,   sinZ,   0,  0,
        --     -sinZ,  cosZ,   0,  0,
        --     0,      0,      1,      0,
        --     (pos1[1] + pos2[1]) * 0.5, (pos1[2] + pos2[2]) * 0.5, (pos1[3] + pos2[3]) * 0.5, 1
        -- }

        local sinY = pos2[3] - pos1[3]
        local cosY = _lengthZ
        local _lengthY = math.sqrt(sinY * sinY + cosY * cosY)
        sinY, cosY = sinY / _lengthY, cosY / _lengthY

        -- local transfY = {
        --     cosY,   0,  sinY,   0,
        --     0,      1,  0,      0,
        --     -sinY,  0,  cosY,   0,
        --     0,      0,  0,      1
        -- }

        return {
            cosZ * cosY,    sinZ * cosY,    sinY,       0,
            -sinZ,          cosZ,           0,          0,
            -cosZ * sinY,   -sinZ * sinY,   cosY,       0,
            (pos1[1] + pos2[1]) * 0.5,  (pos1[2] + pos2[2]) * 0.5,  (pos1[3] + pos2[3]) * 0.5,  1
        }
    end,
    getZShiftFor0mPlatform = function (result, nTerminal)
        if result.laneZs[nTerminal] == constants.platformHeights._0cm.aboveGround then
            return -0.3
        end
        return 0
    end,
    -- returns an integer starting at 0, it can be positive or negative
    getVariant = function(params, slotId)
        local _modules = params.modules
        local variant = 0
        if type(_modules) == 'table'
        and type(_modules[slotId]) == 'table'
        and type(_modules[slotId].variant) == 'number' then
            variant = _modules[slotId].variant or 0
        end
        return variant
    end,
}
privateFuncs.axialAreas = {
    addCargoLaneToSelf = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        -- if not(params.modules[result.mangleId(nTerminal, nTrackEdge, constants.idBases.platformHeadSlotId)]) then return end

        local cpl = terminalData.centrePlatformsRelative[nTrackEdge]
        local cwa = nil
        if cpl.width <= 5 or not(terminalData.isTrackOnPlatformLeft) then
            cwa = terminalData.cargoWaitingAreasRelative[1][nTrackEdge]
        elseif cpl.width <= 10 then
            cwa = terminalData.cargoWaitingAreasRelative[2][nTrackEdge]
        elseif cpl.width <= 15 then
            cwa = terminalData.cargoWaitingAreasRelative[3][nTrackEdge]
        else
            cwa = terminalData.cargoWaitingAreasRelative[4][nTrackEdge]
        end

        local innerPos123 = nTrackEdge == 1 and cwa.posTanX2[1][1] or cwa.posTanX2[2][1]
        innerPos123 = transfUtils.getPositionRaisedBy(innerPos123, result.laneZs[nTerminal])
        local outerPos123 = transfUtils.transf2Position(slotTransf)
        if comparisonUtils.isVec3sCloserThan(innerPos123, outerPos123, 0.001) then return end

        local _lane2AreaTransf = transfUtils.get1MLaneTransf(innerPos123, outerPos123)
        result.models[#result.models+1] = {
            id = constants.passengerLaneModelId,
            slotId = slotId,
            transf = _lane2AreaTransf,
            tag = tag
        }
    end,
    addExitPole = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        local isCargoTerminal = terminalData.isCargo
        local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, terminalData, nTrackEdge)
        local perronModelId = 'lollo_freestyle_train_station/asset/era_c_perron_number.mdl'
        if (isCargoTerminal) then
            perronModelId = 'lollo_freestyle_train_station/asset/cargo_perron_number.mdl'
        elseif eraPrefix == constants.eras.era_b.prefix then
            perronModelId = 'lollo_freestyle_train_station/asset/era_b_perron_number_plain.mdl'
        elseif eraPrefix == constants.eras.era_a.prefix then
            perronModelId = 'lollo_freestyle_train_station/asset/era_a_perron_number.mdl'
        end
        result.models[#result.models + 1] = {
            id = perronModelId,
            slotId = slotId,
            -- transf = transfUtils.getTransf_Shifted(slotTransf, {-0.5, 0.5, 0}),
            transf = transfUtils.getTransf_Shifted(slotTransf, {-0.2, 0.8, 0}),
            tag = tag
        }
        -- the model index must be in base 0 !
        result.labelText[#result.models - 1] = { tostring(nTerminal), "↑" }
    end,
    addPassengerLaneToSelf = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        -- not suitable for cargo elements
        logger.print('axialAreas.addPassengerLaneToSelf starting, t =', tostring(nTerminal), ', nTrackEdge =', tostring(nTrackEdge))
        -- no platform head => no lane
        local headInfo = result.getOccupiedInfo4PlatformHeads(nTerminal, nTrackEdge)
        if headInfo == nil
        or type(headInfo.xShift) ~= 'number'
        or headInfo.xShift == 0 -- lanes with length 0 crash the game
        -- or terminalData.isCargo
        then return end

        local innerPos123 = result.terminateConstructionHookInfo.autoStitchableInnerHeadPositions_by_T_I[nTerminal]
            and result.terminateConstructionHookInfo.autoStitchableInnerHeadPositions_by_T_I[nTerminal][nTrackEdge]
            and result.terminateConstructionHookInfo.autoStitchableInnerHeadPositions_by_T_I[nTerminal][nTrackEdge].pos
        logger.print('innerPos123 =') logger.debugPrint(innerPos123)
        if not(innerPos123) then return end

        local outerPos123 = transfUtils.transf2Position(slotTransf)
        logger.print('outerPos123 =') logger.debugPrint(outerPos123)
        if comparisonUtils.isVec3sCloserThan(innerPos123, outerPos123, 0.001) then return end

        local laneTransf = transfUtils.get1MLaneTransf(innerPos123, outerPos123)
        result.models[#result.models+1] = {
            id = constants.passengerLaneModelId,
            slotId = slotId,
            transf = laneTransf,
            tag = tag
        }
    end,
    getMNAdjustedTransf = function(params, slotId, slotTransf)
        local variant = privateFuncs.getVariant(params, slotId)
        local tilt = privateFuncs.getFromVariant_AxialAreaTilt(variant)
        -- return transfUtilsUG.mul(slotTransf, transfUtilsUG.rotY(tilt))
        return transfUtils.getTransf_YRotated(slotTransf, tilt)
    end,
}
privateFuncs.deco = {
    addWallAcross = function(cpf, isLowIEnd, result, tag, wallModelId, absDeltaY, isTrackOnPlatformLeft, wallTransf, ii, iMax, wallBaseModelId)
        if absDeltaY <= 0 then return end
        local sideWallBase = (isLowIEnd ~= isTrackOnPlatformLeft)
            and {-0.5, 0, 0}
            or {0.5, 0, 0}
        local outerPos = transfUtils.getVec123Transformed(sideWallBase, wallTransf)

        local sideWallBaseFront = (isLowIEnd ~= isTrackOnPlatformLeft)
            and {-0.5, -absDeltaY, 0}
            or {0.5, -absDeltaY, 0}
        local innerPos = transfUtils.getVec123Transformed(sideWallBaseFront, wallTransf)
--[[
        local testPegZ = 0
        result.models[#result.models+1] = {
            id = 'lollo_freestyle_train_station/icon/blue.mdl',
            transf = {
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                outerPos[1], outerPos[2], outerPos[3] + testPegZ + 0.5, 1
            },
            tag = tag
        }
        result.models[#result.models+1] = {
            id = 'lollo_freestyle_train_station/icon/orange.mdl',
            transf = {
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                innerPos[1], innerPos[2], innerPos[3] + testPegZ + 0.0, 1
            },
            tag = tag
        }
]]
        local lengthAcross = absDeltaY
        local sinZ = (outerPos[2] - innerPos[2]) / lengthAcross
        local cosZ = (outerPos[1] - innerPos[1]) / lengthAcross

        local sinX, cosX = 0, 1
        -- if isVertical then
        --     sinX, cosX = 0, 1
        -- else
        --     local cpfPos1, cpfPos2 = cpf.posTanX2[1][1], cpf.posTanX2[2][1]
        --     sinX = cpfPos2[3] - cpfPos1[3]
        --     cosX = math.sqrt((cpfPos2[1] - cpfPos1[1]) * (cpfPos2[1] - cpfPos1[1]) + (cpfPos2[2] - cpfPos1[2]) * (cpfPos2[2] - cpfPos1[2]))
        --     local lengthX = math.sqrt(sinX * sinX + cosX * cosX)
        --     sinX, cosX = sinX / lengthX, cosX / lengthX

        --     if isLowIEnd then
        --         sinX = -sinX -- invert
        --     end
        -- end
        -- logger.print('sinX, cosX =', sinX, cosX)

        local flipShiftTiltTransf = (isLowIEnd == isTrackOnPlatformLeft)
            and {
                -1, 0, 0, 0,
                0, -cosX, sinX, 0,
                0, sinX, cosX, 0,
                0, -0.05, 0, 1 -- this tiny shift at [14] accounts for the wall thickness and the model transf Y
            }
            or {
                1, 0, 0, 0,
                0, cosX, sinX, 0,
                0, -sinX, cosX, 0,
                0, 0.05, 0, 1 -- this tiny shift at [14] accounts for the wall thickness and the model transf Y
            }

        for p = 1, lengthAcross, 1 do
            local transf4P = transfUtilsUG.mul(
                {
                    cosZ, sinZ, 0, 0,
                    -sinZ, cosZ, 0, 0,
                    0, 0, 1, 0,
                    innerPos[1] + (p-0.5) * cosZ, innerPos[2] + (p-0.5) * sinZ, innerPos[3], 1
                },
                flipShiftTiltTransf
            )
            result.models[#result.models+1] = {
                id = wallModelId,
                tag = tag,
                transf = transf4P,
            }
            if wallBaseModelId ~= nil and cpf.type == 0 then -- only on ground
                result.models[#result.models+1] = {
                    id = wallBaseModelId,
                    tag = tag,
                    transf = transf4P,
                }
            end
            -- logger.print('transf 4 p = ') logger.debugPrint(transf4P)
        end
        -- close the last bit if it is shorter than 1 metre - remember walls are all 1 metre wide
        if lengthAcross > math.floor(absDeltaY) then
            local myTransf = transfUtilsUG.mul(
                {
                    cosZ, sinZ, 0, 0,
                    -sinZ, cosZ, 0, 0,
                    0, 0, 1, 0,
                    innerPos[1] + (lengthAcross-0.5) * cosZ, innerPos[2] + (lengthAcross-0.5) * sinZ, innerPos[3], 1
                },
                flipShiftTiltTransf
            )
            result.models[#result.models+1] = {
                id = wallModelId,
                tag = tag,
                transf = myTransf,
            }
            if wallBaseModelId ~= nil and cpf.type == 0 then -- only on ground
                result.models[#result.models+1] = {
                    id = wallBaseModelId,
                    tag = tag,
                    transf = myTransf,
                }
            end
        end
--[[
        local testPegZ = 0
        if isLowIEnd then
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/blue.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    posInwards[1], posInwards[2], posInwards[3] + testPegZ, 1
                },
                tag = tag
            }
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/orange.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1.1, 0,
                    posOutwards[1], posOutwards[2], posOutwards[3] + testPegZ, 1
                },
                tag = tag
            }
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/lilac.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 0.5, 0,
                    posTanX2_Inwards[2][1][1], posTanX2_Inwards[2][1][2], posTanX2_Inwards[2][1][3] + testPegZ, 1
                },
                tag = tag
            }
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/yellow.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 0.5, 0,
                    posTanX2_Outwards[2][1][1], posTanX2_Outwards[2][1][2], posTanX2_Outwards[2][1][3] + testPegZ + 0.1, 1
                },
                tag = tag
            }
        else -- High i end
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/lilac.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1.2, 0,
                    posInwards[1], posInwards[2], posInwards[3] + testPegZ, 1
                },
                tag = tag
            }
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/yellow.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1.3, 0,
                    posOutwards[1], posOutwards[2], posOutwards[3] + testPegZ, 1
                },
                tag = tag
            }
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/blue.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 0.5, 0,
                    posTanX2_Inwards[1][1][1], posTanX2_Inwards[1][1][2], posTanX2_Inwards[1][1][3] + testPegZ + 0.2, 1
                },
                tag = tag
            }
            result.models[#result.models+1] = {
                id = 'lollo_freestyle_train_station/icon/orange.mdl',
                transf = {
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 0.5, 0,
                    posTanX2_Outwards[1][1][1], posTanX2_Outwards[1][1][2], posTanX2_Outwards[1][1][3] + testPegZ + 0.3, 1
                },
                tag = tag
            }
        end
        ]]
    end,
    addWallBehind = function (result, tag, wallBehindBaseModelId, wallBehindModelId, wallTransf, widthAboveNil, xScaleFactor, eraPrefix, laneZ)
        local wallBehindTransf
        if xScaleFactor > 1 then
            -- walls behind are 1 m thick
            local xScaleFactor_WallBehind = (widthAboveNil + 1) / widthAboveNil
            wallBehindTransf = transfUtils.getTransf_XScaled(wallTransf, xScaleFactor_WallBehind)
        else
            wallBehindTransf = wallTransf
        end
        result.models[#result.models+1] = {
            id = wallBehindModelId,
            transf = wallBehindTransf,
            tag = tag
        }
        result.models[#result.models+1] = {
            id = wallBehindBaseModelId,
            transf = wallBehindTransf,
            tag = tag
        }

        local faceTransformed = transfUtils.getFaceTransformed_FAST(
            wallBehindTransf,
            {
                {-0.5, 0, -laneZ, 1}, -- put the terrain level with wallBehindBase, which is 1.4m high, plus a little something to get the wall jammed in
                {-0.5, 0.5, -laneZ, 1}, -- {-0.5, 1, -laneZ, 1}, -- smaller y integrates better with steep slopes but the earth might come into the station
                {0.5, 0.5, -laneZ, 1}, -- {0.5, 1, -laneZ, 1}, -- smaller y integrates better with steep slopes but the earth might come into the station
                {0.5, 0, -laneZ, 1},
                -- {x, positive outwards, z, 1}
            }
        )
        result.groundFaces[#result.groundFaces+1] = {
            face = faceTransformed,
            -- loop = true,
            modes = {
                {
                    type = 'FILL',
                    -- key = 'shared/asphalt_01.gtex.lua' --'shared/gravel_03.gtex.lua'
                    -- key = constants.era_c_groundFacesStrokeOuterKey
                    key = constants[eraPrefix .. 'groundFacesFillKey'],
                },
                -- {
                --     type = 'STROKE_OUTER',
                --     key = 'shared/asphalt_01.gtex.lua' --'shared/gravel_03.gtex.lua'
                -- }
            }
        }

        result.terrainAlignmentLists[#result.terrainAlignmentLists + 1] = {
            faces = { faceTransformed }, -- Z is accounted here
            optional = true,
            -- slopeHigh = 9.6,
            -- slopeLow = 9.6,
            slopeHigh = constants.slopeHigh,
            slopeLow = constants.slopeLow,
            type = 'EQUAL', -- GREATER, LESS
        }
    end,
    ---comment
    ---@param params any
    ---@param slotId integer
    ---@return 0|1|2
    getMNAdjustedValue_0_To_2_Cycling = function(params, slotId)
        local variant = privateFuncs.getVariant(params, slotId)
        local result = privateFuncs.getFromVariant_0_to_1(variant, 3) * 2
        -- logger.print('getMNAdjustedValue_0_To_2_Cycling; variant = ' .. tostring(variant) .. '; result = ' .. tostring(result))
        return result or 0
    end,
    getStationSignFineIndexes = function(params, nTerminal, terminalData)
        local results = {}
        for ii = 3, #terminalData.centrePlatformsFineRelative - 2, constants.maxPassengerWaitingAreaEdgeLength * 6 do
            results[ii] = true
        end
        return results
    end,
    getWallBaseModelId = function(params, eraPrefix)
        local wallModelId = 'lollo_freestyle_train_station/trackWalls/era_c_wall_base_5m.mdl'
        if eraPrefix == constants.eras.era_a.prefix then
            wallModelId = 'lollo_freestyle_train_station/trackWalls/era_a_wall_base_5m.mdl'
        elseif eraPrefix == constants.eras.era_b.prefix then
            wallModelId = 'lollo_freestyle_train_station/trackWalls/era_b_wall_base_5m.mdl'
        end
        return wallModelId
    end,
    getWallBehindBaseModelId = function(params, eraPrefix, isWallThick)
        local wallModelId
        if isWallThick then
            if eraPrefix == constants.eras.era_a.prefix then
                wallModelId = 'lollo_freestyle_train_station/trackWalls/behind/era_a_wall_base_5m_2m_thick.mdl'
            elseif eraPrefix == constants.eras.era_b.prefix then
                wallModelId = 'lollo_freestyle_train_station/trackWalls/behind/era_b_wall_base_5m_2m_thick.mdl'
            else
                wallModelId = 'lollo_freestyle_train_station/trackWalls/behind/era_c_wall_base_5m_2m_thick.mdl'
            end
        else
            if eraPrefix == constants.eras.era_a.prefix then
                wallModelId = 'lollo_freestyle_train_station/trackWalls/behind/era_a_wall_base_5m.mdl'
            elseif eraPrefix == constants.eras.era_b.prefix then
                wallModelId = 'lollo_freestyle_train_station/trackWalls/behind/era_b_wall_base_5m.mdl'
            else
                wallModelId = 'lollo_freestyle_train_station/trackWalls/behind/era_c_wall_base_5m.mdl'
            end
        end

        return wallModelId
    end,
    getWallBehindModelId = function(wall_low_5m_ModelId, isWallThick)
        local wallBehindLowModelId
        if isWallThick then
            if wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tiled/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/iron_glass_copper/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/iron/wall_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/arco_mattoni/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/bricks/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tunnely/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tunnely_light/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_light_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/fence_wood/fence_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/fence_bricks_stone/fence_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/fence_mattoni/square_fence_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/concrete_plain/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tiled_large_stripes/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/concrete_modern/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/metal_glass/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/staccionata_fs/modelled_wall_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m_2m_thick.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/staccionata_fs_tall/modelled_wall_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m_2m_thick.mdl'
            end
        else
            if wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tiled/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/iron_glass_copper/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/iron/wall_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/arco_mattoni/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/bricks/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tunnely/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tunnely_light/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/tunnely_light_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/fence_wood/fence_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/fence_bricks_stone/fence_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/fence_mattoni/square_fence_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/brick_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/concrete_plain/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/tiled_large_stripes/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/concrete_modern/wall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/metal_glass/platformWall_low_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/staccionata_fs/modelled_wall_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m.mdl'
            elseif wall_low_5m_ModelId == 'lollo_freestyle_train_station/platformWalls/staccionata_fs_tall/modelled_wall_5m.mdl' then
                wallBehindLowModelId = 'lollo_freestyle_train_station/platformWalls/behind/concrete_wall_low_5m.mdl'
            end
        end

        return wallBehindLowModelId
    end,
}
privateFuncs.edges = {
    _addTrackEdges = function(result, tag2nodes, params, nTerminal, terminalData)
        logger.print('_addTrackEdges starting for terminal =', nTerminal)
        local _modules = params.modules

        local _isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
        logger.print('_isTrackOnPlatformLeft =', tostring(_isTrackOnPlatformLeft))
        local platformHead1Module = _modules[slotHelpers.mangleId(nTerminal, 1, constants.idBases.platformHeadSlotId)]
        local platformHeadNModule = _modules[slotHelpers.mangleId(nTerminal, #terminalData.centrePlatformsRelative, constants.idBases.platformHeadSlotId)]
        logger.print('platformHead1Module =') logger.debugPrint(platformHead1Module)
        logger.print('platformHeadNModule =') logger.debugPrint(platformHeadNModule)
        logger.print('terminalData.trackEdgeListVehicleNode0Index =', tostring(terminalData.trackEdgeListVehicleNode0Index))
        logger.print('terminalData.trackEdgeListVehicleNode1Index =', tostring(terminalData.trackEdgeListVehicleNode1Index))
        local _getVehicleNodeIndex = function()
            -- these things were added in Jan 2024, leave if they are not there
            if terminalData.trackEdgeListVehicleNode0Index == nil or terminalData.trackEdgeListVehicleNode1Index == nil then return nil end
            -- leave if no platform heads added
            if platformHead1Module == nil and platformHeadNModule == nil then return nil end

            -- positions from the track arrays, which are absolute
            local _inverseMainTransf = params.inverseMainTransf
            local vn1Index = math.min(terminalData.trackEdgeListVehicleNode0Index, terminalData.trackEdgeListVehicleNode1Index)
            local vnNIndex = math.max(terminalData.trackEdgeListVehicleNode0Index, terminalData.trackEdgeListVehicleNode1Index)
            local telVn1 = terminalData.trackEdgeLists[vn1Index]
            local telVnN = terminalData.trackEdgeLists[vnNIndex]
            if telVn1 == nil or telVnN == nil then logger.warn('telVn1 == nil or telVnN == nil') return nil end
            local tel1 = terminalData.trackEdgeLists[1]
            local telN = terminalData.trackEdgeLists[#terminalData.trackEdgeLists]
            if tel1 == nil or telN == nil then logger.warn('tel1 == nil or telN == nil') return nil end
            local tel1Pos = transfUtils.getPosTanX2Transformed(tel1.posTanX2, _inverseMainTransf)[1][1]
            local telNPos = transfUtils.getPosTanX2Transformed(telN.posTanX2, _inverseMainTransf)[2][1]

            -- positions from the NW-based grid, which is relative
            local cplPos = platformHead1Module ~= nil
                and terminalData.centrePlatformsRelative[1].posTanX2[1][1]
                or terminalData.centrePlatformsRelative[#terminalData.centrePlatformsRelative].posTanX2[2][1]

            local vehicleNodeIndex = transfUtils.getPositionsDistance_power2(cplPos, tel1Pos) < transfUtils.getPositionsDistance_power2(cplPos, telNPos)
                and vn1Index
                or vnNIndex
            if logger.isExtendedLog() then
                print('*** _getVehicleNodeIndex is about to return', tostring(vehicleNodeIndex))
            --     print('terminalData.centrePlatformsRelative[1].posTanX2[1][1] =') debugPrint(terminalData.centrePlatformsRelative[1].posTanX2[1][1])
            --     print('terminalData.centrePlatformsRelative[#terminalData.centrePlatformsRelative].posTanX2[2][1] =') debugPrint(terminalData.centrePlatformsRelative[#terminalData.centrePlatformsRelative].posTanX2[2][1])
            --     print('cplPos =') debugPrint(cplPos)
            --     print('...')
            --     print('tel1Pos =') debugPrint(tel1Pos)
            --     print('telNPos =') debugPrint(telNPos)
            --     print('terminalData.trackEdgeLists[vehicleNodeIndex] =') debugPrint(terminalData.trackEdgeLists[vehicleNodeIndex])
            --     print('terminalData.trackEdgeLists[vn1Index] =') debugPrint(terminalData.trackEdgeLists[vn1Index])
            --     print('terminalData.trackEdgeLists[vnNIndex] =') debugPrint(terminalData.trackEdgeLists[vnNIndex])
            end
            return vehicleNodeIndex
        end
        local vehicleNodeIndex = _getVehicleNodeIndex() or terminalData.trackEdgeListMidIndex
        result.terminateConstructionHookInfo.vehicleNodes[nTerminal] = (#result.edgeLists + vehicleNodeIndex) * 2 - 2

        logger.print('#terminalData.trackEdgeLists =', tostring(#terminalData.trackEdgeLists))
        logger.print('#terminalData.platformEdgeLists =', tostring(#terminalData.platformEdgeLists))
        logger.print('result.terminateConstructionHookInfo.vehicleNodes[nTerminal] =', tostring(result.terminateConstructionHookInfo.vehicleNodes[nTerminal]))

        local forceCatenary = 0
        local trackElectrificationModuleKey = slotHelpers.mangleId(nTerminal, 0, constants.idBases.trackElectrificationSlotId)
        if _modules[trackElectrificationModuleKey] ~= nil then
            if _modules[trackElectrificationModuleKey].name == constants.trackElectrificationYesModuleFileName then
                forceCatenary = 2
            elseif _modules[trackElectrificationModuleKey].name == constants.trackElectrificationNoModuleFileName then
                forceCatenary = 1
            end
        end
        logger.print('forceCatenary =', forceCatenary)
        local forceFast = 0
        local trackSpeedModuleKey = slotHelpers.mangleId(nTerminal, 0, constants.idBases.trackSpeedSlotId)
        if _modules[trackSpeedModuleKey] ~= nil then
            if _modules[trackSpeedModuleKey].name == constants.trackSpeedFastModuleFileName then
                forceFast = 2
            elseif _modules[trackSpeedModuleKey].name == constants.trackSpeedSlowModuleFileName then
                forceFast = 1
            end
        end
        logger.print('forceFast =', forceFast)
    
        local maxI = #terminalData.trackEdgeLists
        for i = 1, maxI do
            local tel = terminalData.trackEdgeLists[i]
    
            local overriddenCatenary = tel.catenary
            if forceCatenary == 1 then overriddenCatenary = false
            elseif forceCatenary == 2 then overriddenCatenary = true
            end
    
            local overriddenTrackType = tel.trackTypeName
            if forceFast == 1 then overriddenTrackType = 'standard.lua'
            elseif forceFast == 2 then overriddenTrackType = 'high_speed.lua'
            end
    
            local newEdgeList = {
                alignTerrain = tel.type == 0 or tel.type == 2, -- only align on ground and in tunnels
                edges = transfUtils.getPosTanX2Transformed(tel.posTanX2, params.inverseMainTransf),
                edgeType = tel.edgeType,
                edgeTypeName = tel.edgeTypeName,
                -- freeNodes = {}, -- useless
                params = {
                    catenary = overriddenCatenary,
                    type = overriddenTrackType,
                },
                snapNodes = {},
                tag2nodes = tag2nodes,
                type = 'TRACK'
                -- nTerminal = t, -- won't work
                -- nTrackEdge = i, -- won't work
            }

            if i == 1 then
                -- newEdgeList.freeNodes[#newEdgeList.freeNodes+1] = 0
                newEdgeList.snapNodes[#newEdgeList.snapNodes+1] = 0
            end
            if i == maxI then
                -- newEdgeList.freeNodes[#newEdgeList.freeNodes+1] = 1
                newEdgeList.snapNodes[#newEdgeList.snapNodes+1] = 1
            end

            -- LOLLO NOTE the edges won't snap to the neighbours
            -- unless you rebuild those neighbours, by hand or by script,
            -- and make them snap to the station own nodes.
            result.edgeLists[#result.edgeLists+1] = newEdgeList

            if not(result.trackEdgeListsIndexes) then result.trackEdgeListsIndexes = {} end
            if not(result.trackEdgeListsIndexes[nTerminal]) then result.trackEdgeListsIndexes[nTerminal] = {} end
            result.trackEdgeListsIndexes[nTerminal][i] = #result.edgeLists
        end
    end,
    _addPlatformEdges = function(result, tag2nodes, params, nTerminal, terminalData)
        local maxI = #terminalData.platformEdgeLists
        for i = 1, maxI do
            local pel = terminalData.platformEdgeLists[i]

            local newEdgeList = {
                -- UG TODO LOLLO TODO never mind if I align the terrain or I change the track materials,
                -- the game will always draw ballast in the underpasses - bridges are less affected.
                -- The cause is, when you snap a platform-track along a track, the terrain gets levelled
                -- and painted. It wins over terrainAlignments and over groundTextures with very high prios.
                -- The only thing that works is a material with 
                -- polygon_offset = {
                --     factor = -999,
                --     forceDepthWrite = true,
                --     units = -999,
                -- },
                -- but then it shines through everything else.
                -- You can see it with a platform that snaps to a track and then stretches away from it:
                -- In the free piece, you will see the underpasses properly; however, as soon as you lay any track 
                -- alongside, the terrain will come up. If the track does not snap, the underpass will look fine instead.
                -- The easy way around it is not to draw the platform edge;
                -- this will make trouble when snapping parallel platform, which far outweighs the optical benefit
                -- of underpasses.
                -- It will also make for missing bits of bridges.

                -- You can also lay an invisible track (after making it available)
                -- and snap some other track along it: the ballastMaterial of the latter will win and extend under the invisible track,
                -- never mind how many ypu have.
                -- The game will create a foundation (lots of little parallelepipeds),
                -- paint it with the winning ballast material
                -- and extend it to all snapped tracks.
                -- Unless we find the undocumented fallback - it looks like one. There is config/ground/texture/fallback.lua,
                -- but id does nothing.

                -- The winner does not seem affected by height.
                -- Neither by the material priority.
                -- It seems to have a degree of randomness, but the sucky part is: there is a winner and it takes all.
                -- So, even if I set a transparent ballastMaterial and I manage to make it win (not that I could manage so far),
                -- also the normal tracks will receive a transparent ballast.
                alignTerrain = pel.type == 0 or pel.type == 2, -- only align on ground and in tunnels
                edges = transfUtils.getPosTanX2Transformed(pel.posTanX2, params.inverseMainTransf),
                edgeType = pel.edgeType,
                edgeTypeName = pel.edgeTypeName,
                -- freeNodes = {}, -- useless
                params = {
                    -- type = pel.trackTypeName,
                    type = trackUtils.getInvisibleTwinFileName(pel.trackTypeName),
                    catenary = false --pel.catenary
                },
                snapNodes = {},
                tag2nodes = tag2nodes,
                type = 'TRACK'
            }

            if i == 1 then
                -- newEdgeList.freeNodes[#newEdgeList.freeNodes+1] = 0
                newEdgeList.snapNodes[#newEdgeList.snapNodes+1] = 0
            end
            if i == maxI then
                -- newEdgeList.freeNodes[#newEdgeList.freeNodes+1] = 1
                newEdgeList.snapNodes[#newEdgeList.snapNodes+1] = 1
            end

            result.edgeLists[#result.edgeLists+1] = newEdgeList

            if not(result.platformEdgeListsIndexes) then result.platformEdgeListsIndexes = {} end
            if not(result.platformEdgeListsIndexes[nTerminal]) then result.platformEdgeListsIndexes[nTerminal] = {} end
            result.platformEdgeListsIndexes[nTerminal][i] = #result.edgeLists
        end
    end,
    _getNNodesInTerminalsSoFar = function(params, nTerminal)
        local result = 0
        for tt = 1, nTerminal - 1 do
            if params.terminals[tt] ~= nil then
                if params.terminals[tt].platformEdgeLists ~= nil then
                    result = result + #params.terminals[tt].platformEdgeLists * 2
                end
                if params.terminals[tt].trackEdgeLists ~= nil then
                    result = result + #params.terminals[tt].trackEdgeLists * 2
                end
            end
        end
        return result
    end,
}
privateFuncs.flatAreas = {
    addCargoLaneToSelf = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        local cpl = terminalData.centrePlatformsRelative[nTrackEdge]
        local cwa = nil
        if cpl.width <= 5 or terminalData.isTrackOnPlatformLeft then
            cwa = terminalData.cargoWaitingAreasRelative[1][nTrackEdge]
        elseif cpl.width <= 10 then
            cwa = terminalData.cargoWaitingAreasRelative[2][nTrackEdge]
        elseif cpl.width <= 15 then
            cwa = terminalData.cargoWaitingAreasRelative[3][nTrackEdge]
        else
            cwa = terminalData.cargoWaitingAreasRelative[4][nTrackEdge]
        end

        local innerPos123 = transfUtils.getPositionRaisedBy(cwa.posTanX2[1][1], result.laneZs[nTerminal])
        local outerPos123 = transfUtils.transf2Position(slotTransf)
        if comparisonUtils.isVec3sCloserThan(innerPos123, outerPos123, 0.001) then return end

        local _lane2AreaTransf = transfUtils.get1MLaneTransf(innerPos123, outerPos123)
        result.models[#result.models+1] = {
            id = constants.passengerLaneModelId,
            slotId = slotId,
            transf = _lane2AreaTransf,
            tag = tag
        }
    end,
    addExitPole = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        local isCargoTerminal = terminalData.isCargo
        local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, terminalData, nTrackEdge)
        local perronModelId = 'lollo_freestyle_train_station/asset/era_c_perron_number.mdl'
        if (isCargoTerminal) then
            perronModelId = 'lollo_freestyle_train_station/asset/cargo_perron_number.mdl'
        elseif eraPrefix == constants.eras.era_b.prefix then
            perronModelId = 'lollo_freestyle_train_station/asset/era_b_perron_number_plain.mdl'
        elseif eraPrefix == constants.eras.era_a.prefix then
            perronModelId = 'lollo_freestyle_train_station/asset/era_a_perron_number.mdl'
        end
        result.models[#result.models + 1] = {
            id = perronModelId,
            slotId = slotId,
            -- transf = transfUtilsUG.mul(slotTransf, {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  -0.5, 0.5, 0, 1}),
            transf = transfUtils.getTransf_Shifted(slotTransf, {-0.5, 0.5, 0}),
            tag = tag
        }
        -- the model index must be in base 0 !
        result.labelText[#result.models - 1] = { tostring(nTerminal), "↑" }
    end,
    addPassengerLaneToSelf = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        local crossConnectorPosTanX2 = terminalData.crossConnectorsRelative[nTrackEdge].posTanX2
        local innerPos123 = transfUtils.getPositionRaisedBy(crossConnectorPosTanX2[2][1], result.laneZs[nTerminal])
        local outerPos123 = transfUtils.transf2Position(slotTransf)
        if comparisonUtils.isVec3sCloserThan(innerPos123, outerPos123, 0.001) then return end

        local lane2AreaTransf = transfUtils.get1MLaneTransf(innerPos123, outerPos123)
        result.models[#result.models+1] = {
            id = constants.passengerLaneModelId,
            slotId = slotId,
            transf = lane2AreaTransf,
            tag = tag
        }
    end,
    getMNAdjustedTransf = function(params, slotId, slotTransf, isFlush)
        local variant = privateFuncs.getVariant(params, slotId)
        local deltaZ = privateFuncs.getFromVariant_FlatAreaHeight(variant, isFlush)
        return transfUtils.getTransf_ZShifted(slotTransf, deltaZ)
    end,
}
privateFuncs.openStairs = {
    addExitPole = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge, eraPrefix)
        local isCargoTerminal = terminalData.isCargo
        local perronModelId = 'lollo_freestyle_train_station/asset/era_c_perron_number.mdl'
        if (isCargoTerminal) then
            perronModelId = 'lollo_freestyle_train_station/asset/cargo_perron_number.mdl'
        elseif eraPrefix == constants.eras.era_b.prefix then
            perronModelId = 'lollo_freestyle_train_station/asset/era_b_perron_number_plain.mdl'
        elseif eraPrefix == constants.eras.era_a.prefix then
            perronModelId = 'lollo_freestyle_train_station/asset/era_a_perron_number.mdl'
        end
        result.models[#result.models + 1] = {
            id = perronModelId,
            slotId = slotId,
            -- transf = transfUtils.getTransf_Shifted(slotTransf, {0.2, 0.8, 0}),
            transf = transfUtils.getTransf_Shifted(transfUtils.getTransf_Scaled(slotTransf, {0.667, 0.667, 0.667}), {0.3, 1.3, 0}),
            tag = tag
        }
        -- the model index must be in base 0 !
        result.labelText[#result.models - 1] = { tostring(nTerminal), "↑" }
    end,
    getExitModelTransf = function(slotTransf, slotId, params)
        local variant = privateFuncs.getVariant(params, slotId)
        local tilt = privateFuncs.getFromVariant_BridgeTilt(variant)
        return transfUtils.getTransf_YRotated(slotTransf, tilt)
    end,
    getPedestrianBridgeModelId = function(length, eraPrefix, isWithEdge)
        -- eraPrefix is a string like 'era_a_'
        local lengthStr = '4'
        if length < 3 then lengthStr = '2'
        elseif length < 5 then lengthStr = '4'
        elseif length < 7 then lengthStr = '6'
        elseif length < 10 then lengthStr = '8'
        elseif length < 14 then lengthStr = '12'
        elseif length < 20 then lengthStr = '16'
        elseif length < 28 then lengthStr = '24'
        elseif length < 40 then lengthStr = '32'
        elseif length < 56 then lengthStr = '48'
        else lengthStr = '64'
        end

        local newEraPrefix = eraPrefix
        if newEraPrefix ~= constants.eras.era_a.prefix and newEraPrefix ~= constants.eras.era_b.prefix and newEraPrefix ~= constants.eras.era_c.prefix then
            newEraPrefix = constants.eras.era_c.prefix
        end

        if isWithEdge then
            return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_with_edge_' .. lengthStr .. 'm.mdl'
        else
            return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_' .. lengthStr .. 'm.mdl'
        end
    end,
}
privateFuncs.platforms = {
    doTerrainFromCoordinates = function(result, nTerminal, groundFacesFillKey, terrainCoordinates)
        local faces = {}
        for tc = 1, #terrainCoordinates do
            local face = { }
            for i = 1, 4 do
                face[i] = {
                    terrainCoordinates[tc][i][1],
                    terrainCoordinates[tc][i][2],
                    terrainCoordinates[tc][i][3],
                    1
                }
            end
            faces[#faces+1] = face
            if groundFacesFillKey ~= nil then
                result.groundFaces[#result.groundFaces + 1] = {
                    face = face, -- Z is ignored here
                    loop = true,
                    modes = {
                        {
                            type = 'FILL',
                            key = groundFacesFillKey,
                        },
                        {
                            type = 'STROKE_OUTER',
                            key = groundFacesFillKey
                        }
                    }
                }
            end
        end
    end,
    getTerrainCoordinates = function(terminalData)
        local terrainCoordinates = {}

        local _cpfs = terminalData.centrePlatformsFineRelative
        for ii = 1, #_cpfs do
            local cpf = _cpfs[ii]
            if cpf.type == 0 then -- only on ground
                local platformWidth = cpf.width
                local innerAreaEdgePosTanX2 = transfUtils.getParallelSidewaysCoarse(
                    cpf.posTanX2,
                    -platformWidth * 0.5
                )
                local outerAreaEdgePosTanX2 = transfUtils.getParallelSidewaysCoarse(
                    cpf.posTanX2,
                    platformWidth * 0.5
                )
                local pos1Inner = innerAreaEdgePosTanX2[1][1]
                local pos2Inner = innerAreaEdgePosTanX2[2][1]
                local pos2Outer = outerAreaEdgePosTanX2[2][1]
                local pos1Outer = outerAreaEdgePosTanX2[1][1]
                terrainCoordinates[#terrainCoordinates+1] = {
                    pos1Inner,
                    pos2Inner,
                    pos2Outer,
                    pos1Outer,
                }
            end
        end
        -- logger.print('terrainCoordinates =') logger.debugPrint(terrainCoordinates)
        return terrainCoordinates
    end,
}
privateFuncs.platformHeads = {
    getHeadModelId = function (eraPrefix, isCargo, isRight, width, platformStyleModuleFileName)
        if isCargo then
			if width < 10 then
                if platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_earth.moduleFileName then
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/earth_cargo_4m_long_10m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/earth_cargo_4m_long_10m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_gravel.moduleFileName then
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/gravel_cargo_4m_long_10m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/gravel_cargo_4m_long_10m_wide_left.mdl'
                else
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'cargo_4m_long_10m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'cargo_4m_long_10m_wide_left.mdl'
                end
            elseif width < 20 then
                if platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_earth.moduleFileName then
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/earth_cargo_4m_long_15m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/earth_cargo_4m_long_15m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_gravel.moduleFileName then
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/gravel_cargo_4m_long_15m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/gravel_cargo_4m_long_15m_wide_left.mdl'
                else
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'cargo_4m_long_15m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'cargo_4m_long_15m_wide_left.mdl'
                end
            else
                if platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_earth.moduleFileName then
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/earth_cargo_4m_long_25m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/earth_cargo_4m_long_25m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_gravel.moduleFileName then
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/gravel_cargo_4m_long_25m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/gravel_cargo_4m_long_25m_wide_left.mdl'
                else
                    return isRight and 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'cargo_4m_long_25m_wide_right.mdl'
                    or 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'cargo_4m_long_25m_wide_left.mdl'
                end
            end
        else
            if width < 5 then
                if platformStyleModuleFileName == constants.passengersPlatformStyles.era_b_db.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_b_db_passengers_4m_long_7_5m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_b_db_passengers_4m_long_7_5m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_1_stripe.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_7_5m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_7_5m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_fs_1_stripe.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_7_5m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_7_5m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_uk_2_stripes.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_7_5m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_7_5m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_2_stripes.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_2s_passengers_4m_long_7_5m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_2s_passengers_4m_long_7_5m_wide_left.mdl'
                else
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'passengers_4m_long_7_5m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'passengers_4m_long_7_5m_wide_left.mdl'
                end
            else
                if platformStyleModuleFileName == constants.passengersPlatformStyles.era_b_db.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_b_db_passengers_4m_long_10m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_b_db_passengers_4m_long_10m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_1_stripe.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_10m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_10m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_fs_1_stripe.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_10m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_10m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_uk_2_stripes.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_10m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_1s_passengers_4m_long_10m_wide_left.mdl'
                elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_2_stripes.moduleFileName then
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_2s_passengers_4m_long_10m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/era_c_db_2s_passengers_4m_long_10m_wide_left.mdl'
                else
                    return isRight
                        and 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'passengers_4m_long_10m_wide_right.mdl'
                        or 'lollo_freestyle_train_station/railroad/platformHeads/' .. eraPrefix .. 'passengers_4m_long_10m_wide_left.mdl'
                end
            end
        end
    end,
}
privateFuncs.slopedAreas = {
    addSlopedCargoAreaDeco = function(result, tag, slotId, params, nTerminal, terminalData, nTrackEdge, eraPrefix, areaWidth, nWaitingAreas, verticalTransfAtPlatformCentre)
        if areaWidth < 5 or nWaitingAreas < 4 then return end

        local isEndFiller = privateFuncs.getIsEndFillerEvery3(nTrackEdge)
        if isEndFiller then return end

        local laneZ = result.laneZs[nTerminal]
        local isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
        local cpl = terminalData.centrePlatformsRelative[nTrackEdge]
        local platformWidth = cpl.width

        local xShift1 = -4.6
        local xShift2 = 4.6
        if (nWaitingAreas % 2) == 0 then
            xShift1 = -3.1
            xShift2 = 3.1
        end

        local yShift = (-platformWidth -areaWidth) / 2
        if not(isTrackOnPlatformLeft) then yShift = -yShift end

        local roofModelId = nil
        if eraPrefix == constants.eras.era_a.prefix then
            roofModelId = 'lollo_freestyle_train_station/asset/cargo_roof_grid_dark_4x4.mdl'
        else
            roofModelId = 'lollo_freestyle_train_station/asset/cargo_roof_grid_4x4.mdl'
        end

        result.models[#result.models + 1] = {
            id = roofModelId,
            slotId = slotId,
            -- transf = transfUtilsUG.mul(verticalTransfAtPlatformCentre, { 0, 1, 0, 0,  -1, 0, 0, 0,  0, 0, 1, 0,  xShift1, yShift, laneZ, 1 }),
            transf = transfUtils.getTransf_ZRotatedP90_Shifted(verticalTransfAtPlatformCentre, {xShift1, yShift, laneZ}),
            tag = tag
        }
        result.models[#result.models + 1] = {
            id = roofModelId,
            slotId = slotId,
            -- transf = transfUtilsUG.mul(verticalTransfAtPlatformCentre, { 0, -1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0,  xShift2, yShift, laneZ, 1 }),
            transf = transfUtils.getTransf_ZRotatedM90_Shifted(verticalTransfAtPlatformCentre, {xShift2, yShift, laneZ}),
            tag = tag
        }
    end,
    addSlopedPassengerAreaDeco = function(result, tag, slotId, params, nTerminal, terminalData, nTrackEdge, eraPrefix, areaWidth, nWaitingAreas, verticalTransfAtPlatformCentre)
        if areaWidth < 5 then return end

        local isEndFiller = privateFuncs.getIsEndFillerEvery3(nTrackEdge)
        if isEndFiller then return end

        local laneZ = result.laneZs[nTerminal]
        local isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
        local cpl = terminalData.centrePlatformsRelative[nTrackEdge]
        local platformWidth = cpl.width

        local xShift = nWaitingAreas <= 4 and -2.0 or 0.0
        local yShift1 = -platformWidth / 2 - 2.8
        local yShift2 = -platformWidth / 2 - 1.0
        local yShift3 = -platformWidth / 2 - 2.1
        if not(isTrackOnPlatformLeft) then yShift1 = -yShift1 yShift2 = -yShift2 yShift3 = -yShift3 end

        local chairsModelId = nil
        local binModelId = nil
        local arrivalsModelId = nil
        if eraPrefix == constants.eras.era_a.prefix then
            chairsModelId = 'lollo_freestyle_train_station/asset/era_a_four_chairs.mdl'
            binModelId = 'lollo_freestyle_train_station/asset/era_a_trashcan.mdl'
            arrivalsModelId = 'lollo_freestyle_train_station/asset/era_a_arrivals_departures_column.mdl'
        elseif eraPrefix == constants.eras.era_b.prefix then
            chairsModelId = 'lollo_freestyle_train_station/asset/era_b_four_chairs.mdl'
            binModelId = 'lollo_freestyle_train_station/asset/era_b_trashcan.mdl'
            arrivalsModelId = 'lollo_freestyle_train_station/asset/era_b_arrivals_departures_column.mdl'
        else
            chairsModelId = 'lollo_freestyle_train_station/asset/era_c_four_chairs.mdl'
            binModelId = 'lollo_freestyle_train_station/asset/era_c_trashcan.mdl'
            arrivalsModelId = 'lollo_freestyle_train_station/asset/tabellone_standing.mdl'
        end

        result.models[#result.models + 1] = {
            id = chairsModelId,
            slotId = slotId,
            -- transf = transfUtilsUG.mul(verticalTransfAtPlatformCentre, { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  xShift + 1.6, yShift1, laneZ, 1 }),
            transf = transfUtils.getTransf_Shifted(verticalTransfAtPlatformCentre, {xShift + 1.6, yShift1, laneZ}),
            tag = tag
        }
        result.models[#result.models + 1] = {
            id = binModelId,
            slotId = slotId,
            -- transf = transfUtilsUG.mul(verticalTransfAtPlatformCentre, { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  xShift + 1.6, yShift2, laneZ, 1 }),
            transf = transfUtils.getTransf_Shifted(verticalTransfAtPlatformCentre, {xShift + 1.6, yShift2, laneZ}),
            tag = tag
        }
        result.models[#result.models + 1] = {
            id = arrivalsModelId,
            slotId = slotId,
            -- transf = transfUtilsUG.mul(verticalTransfAtPlatformCentre, { 0, 1, 0, 0,  -1, 0, 0, 0,  0, 0, 1, 0,  xShift + 6.2, yShift3, laneZ, 1 }),
            transf = transfUtils.getTransf_ZRotatedP90_Shifted(verticalTransfAtPlatformCentre, {xShift + 6.2, yShift3, laneZ}),
            tag = tag
        }
    end,
    _getSlopedAreaInnerDegreeOLD = function(params, nTerminal, nTrackEdge)
        local centrePlatforms = params.terminals[nTerminal].centrePlatformsRelative
    
        local x1 = 0
        local y1 = 0
        local xM = 0
        local yM = 0
        local x2 = 0
        local y2 = 0
        if centrePlatforms[nTrackEdge - 1] ~= nil and centrePlatforms[nTrackEdge] ~= nil and centrePlatforms[nTrackEdge + 1] ~= nil then
            x1 = centrePlatforms[nTrackEdge - 1].posTanX2[1][1][1]
            y1 = centrePlatforms[nTrackEdge - 1].posTanX2[1][1][2]
            x2 = centrePlatforms[nTrackEdge + 1].posTanX2[1][1][1]
            y2 = centrePlatforms[nTrackEdge + 1].posTanX2[1][1][2]
            xM = centrePlatforms[nTrackEdge].posTanX2[1][1][1]
            yM = centrePlatforms[nTrackEdge].posTanX2[1][1][2]
        elseif centrePlatforms[nTrackEdge - 1] ~= nil and centrePlatforms[nTrackEdge] ~= nil then
            x1 = centrePlatforms[nTrackEdge - 1].posTanX2[1][1][1]
            y1 = centrePlatforms[nTrackEdge - 1].posTanX2[1][1][2]
            x2 = centrePlatforms[nTrackEdge].posTanX2[2][1][1]
            y2 = centrePlatforms[nTrackEdge].posTanX2[2][1][2]
            xM = centrePlatforms[nTrackEdge].posTanX2[1][1][1]
            yM = centrePlatforms[nTrackEdge].posTanX2[1][1][2]
        elseif centrePlatforms[nTrackEdge] ~= nil and centrePlatforms[nTrackEdge + 1] ~= nil then
            x1 = centrePlatforms[nTrackEdge].posTanX2[1][1][1]
            y1 = centrePlatforms[nTrackEdge].posTanX2[1][1][2]
            x2 = centrePlatforms[nTrackEdge + 1].posTanX2[2][1][1]
            y2 = centrePlatforms[nTrackEdge + 1].posTanX2[2][1][2]
            xM = centrePlatforms[nTrackEdge].posTanX2[2][1][1]
            yM = centrePlatforms[nTrackEdge].posTanX2[2][1][2]
        else
            logger.warn('cannot get inner degree')
            return privateConstants.slopedAreasOLD.innerDegrees.neutral
        end
    
        local segmentHunch = transfUtils.getDistanceBetweenPointAndStraight(
            {x1, y1, 0},
            {x2, y2, 0},
            {xM, yM, 0}
        )
        -- logger.print('segmentHunch =', segmentHunch)
    
        -- local segmentLength = transfUtils.getPositionsDistance(
        --     centrePlatforms[nTrackEdge - 1].posTanX2[1][1],
        --     centrePlatforms[nTrackEdge + 1].posTanX2[1][1]
        -- )
        -- logger.print('segmentLength =', segmentLength)
        -- if segmentHunch / segmentLength < privateConstants.slopedAreas.hunchLengthRatioToClaimBend then return privateConstants.slopedAreas.innerDegrees.neutral end
        if segmentHunch < privateConstants.slopedAreasOLD.hunchToClaimBend then return privateConstants.slopedAreasOLD.innerDegrees.neutral end
    
        -- a + bx = y
        -- => a + b * x1 = y1
        -- => a + b * x2 = y2
        -- => b * (x1 - x2) = y1 - y2
        -- => b = (y1 - y2) / (x1 - x2)
        -- OR division by zero
        -- => a = y1 - b * x1
        -- => a = y1 - (y1 - y2) / (x1 - x2) * x1
        -- a + b * xM > yM <= this is what we want to know
        -- => y1 - (y1 - y2) / (x1 - x2) * x1 + (y1 - y2) / (x1 - x2) * xM > yM
        -- => y1 * (x1 - x2) - (y1 - y2) * x1 + (y1 - y2) * xM > yM * (x1 - x2)
        -- => (y1 - yM) * (x1 - x2) + (y1 - y2) * (xM - x1) > 0
    
        local innerSign = comparisonUtils.sgn((y1 - yM) * (x1 - x2) + (y1 - y2) * (xM - x1))
    
        if not(params.terminals[nTerminal].isTrackOnPlatformLeft) then innerSign = -innerSign end
        -- logger.print('terminal', nTerminal, 'innerSign =', innerSign)
        return innerSign
    end,
    _getSlopedAreaTweakFactorsOLD = function(innerDegree, areaWidth)
        local waitingAreaScaleFactor = areaWidth * 0.8
    
        -- LOLLO NOTE sloped areas are parallelepipeds that extend the parallelepipeds that make up the platform sideways.
        -- I don't know of any transformation to twist or deform a model, so either I make an arsenal of meshes (no!) or I adjust things.
        -- 1) If I am outside a bend, I must stretch the sloped areas so there are no holes between them.
        -- Inside a bend, I haven't got this problem but I cannot shrink them, either, lest I get holes.
        -- 2) As I approach the centre of a bend, the slope should increase, and it should decrease as I move outwards.
        -- To visualise this, imagine building a helter skelter with horizontal planks, or a tight staircase: the centre will be super steep.
        -- Since there is no transf for this, I tweak the angle around the Y axis.
    
        -- These tricks work to a certain extent, but since I cannot skew or twist my models,
        -- I work out a new cleaner series of segments to follow, instead of extending the platform sideways.
        -- It is cleaner (the Y angle is optimised by construction) but slow, so we run the calculations in advance in the big script.
        -- And we still need to tweak it a little.
    
        -- Using multiple thin parallel extensions is slow and brings nothing at all.
    
        -- The easiest is: leave the narrower slopes since they don't cause much grief, and bridges need them,
        -- and use the terrain for the wider ones. Even the smaller sloped areas need quite a bit of stretch, but they are less sensiitive to the angle problem.
        -- However, the terrain will never look as good as a dedicated model.
        -- local angleYFactor = 1
        local xScaleFactor = 1
        -- local waitingAreaPeriod = 5
        -- outside a bend
        if innerDegree < 0 then
            -- waitingAreaPeriod = 4
            if areaWidth <= 5 then
                xScaleFactor = 1.20
                -- angleYFactor = 1.0625
            elseif areaWidth <= 10 then
                xScaleFactor = 1.30
                -- angleYFactor = 1.10
            elseif areaWidth <= 20 then
                xScaleFactor = 1.40
                -- angleYFactor = 1.20
            end
        -- inside a bend
        elseif innerDegree > 0 then
            -- waitingAreaPeriod = 6
            xScaleFactor = 0.95
            -- if areaWidth <= 5 then
            --     angleYFactor = 0.9
            -- elseif areaWidth <= 10 then
            --     angleYFactor = 0.825
            -- elseif areaWidth <= 20 then
            --     angleYFactor = 0.75
            -- end
        -- more or less straight
        else
            if areaWidth <= 5 then
                xScaleFactor = 1.05
            elseif areaWidth <= 10 then
                xScaleFactor = 1.15
            elseif areaWidth <= 20 then
                xScaleFactor = 1.25
            end
        end
        -- logger.print('xScaleFactor =', xScaleFactor)
        -- logger.print('angleYFactor =', angleYFactor)
    
        return waitingAreaScaleFactor, xScaleFactor
    end,
    isSlopedAreaAllowed = function(cpf, areaWidth)
        return cpf.type == 0 or (cpf.type == 1 and areaWidth <= 2.5)
    end,
    doTerrainFromCoordinates = function(result, nTerminal, groundFacesFillKey, terrainCoordinates, isTerrainFlush)
        local faces = {}
        local deltaZ = isTerrainFlush and (result.laneZs[nTerminal] - 0.1) or (result.laneZs[nTerminal] -constants.stairsAndRampHeight) -- need 0.1 so the module can be removed
        -- local deltaZ = isTerrainFlush and (result.laneZs[nTerminal]) or (result.laneZs[nTerminal] -constants.stairsAndRampHeight)
        for tc = 1, #terrainCoordinates do
            local face = { }
            for i = 1, 4 do
                face[i] = {
                    terrainCoordinates[tc][i][1],
                    terrainCoordinates[tc][i][2],
                    terrainCoordinates[tc][i][3] + deltaZ,
                    1
                }
            end
            faces[#faces+1] = face
            if groundFacesFillKey ~= nil then
                result.groundFaces[#result.groundFaces + 1] = {
                    face = face, -- Z is ignored here
                    loop = true,
                    modes = {
                        {
                            type = 'FILL',
                            key = groundFacesFillKey,
                        },
                        {
                            type = 'STROKE_OUTER',
                            key = groundFacesFillKey
                        }
                    }
                }
            end
        end
        if #faces > 1 then
            result.terrainAlignmentLists[#result.terrainAlignmentLists + 1] = {
                faces = faces, -- Z is accounted here
                optional = true,
                slopeHigh = constants.slopeHigh,
                slopeLow = constants.slopeLow,
                type = 'EQUAL', -- GREATER, LESS
            }
        end
    end,
    getTerrainCoordinates = function(result, params, nTerminal, terminalData, nTrackEdge, isEndFiller, areaWidth, groundFacesFillKey)
        local terrainCoordinates = {}

        local i1 = isEndFiller and nTrackEdge or (nTrackEdge - 1)
        local iN = nTrackEdge + 1
        local isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft

        local _cpfs = terminalData.centrePlatformsFineRelative
        for ii = 1, #_cpfs do
            local cpf = _cpfs[ii]
            local leadingIndex = cpf.leadingIndex
            if leadingIndex > iN then break end
            if cpf.type == 0 then -- only on ground
                if leadingIndex >= i1 then
                    local platformWidth = cpf.width
                    local outerAreaEdgePosTanX2 = transfUtils.getParallelSidewaysCoarse(
                        cpf.posTanX2,
                        (isTrackOnPlatformLeft and (-areaWidth -platformWidth * 0.5) or (areaWidth + platformWidth * 0.5))
                    )
                    local pos1Inner = cpf.posTanX2[1][1]
                    local pos2Inner = cpf.posTanX2[2][1]
                    local pos2Outer = outerAreaEdgePosTanX2[2][1]
                    local pos1Outer = outerAreaEdgePosTanX2[1][1]
                    terrainCoordinates[#terrainCoordinates+1] = {
                        pos1Inner,
                        pos2Inner,
                        pos2Outer,
                        pos1Outer,
                    }
                end
            end
        end
        -- logger.print('terrainCoordinates =') logger.debugPrint(terrainCoordinates)
        return terrainCoordinates
    end,
}
privateFuncs.subways = {
    doTerrain4ClosedSubways = function(result, slotTransf, groundFacesStrokeOuterKey, terrainFace)
        local _groundFacesFillKey = constants[constants.eras.era_c.prefix .. 'groundFacesFillKey']
        -- local groundFace = { -- the ground faces ignore z, the alignment lists don't
        --     {0.0, -0.95, 0, 1},
        --     {0.0, 0.95, 0, 1},
        --     {4.5, 0.95, 0, 1},
        --     {4.5, -0.95, 0, 1},
        -- }
        -- local terrainFace = { -- the ground faces ignore z, the alignment lists don't
        --     {-2.2, -4.15, constants.platformSideBitsZ, 1},
        --     {-2.2, 4.15, constants.platformSideBitsZ, 1},
        --     {4.7, 4.15, constants.platformSideBitsZ, 1},
        --     {4.7, -4.15, constants.platformSideBitsZ, 1},
        -- }
        if type(slotTransf) == 'table' then
            -- vs transfUtils.getFaceTransformed and transfUtils.getFaceTransformed_FAST
            modulesutil.TransformFaces(slotTransf, terrainFace)
        end

        table.insert(
            result.groundFaces,
            {
                -- face = groundFace,
                face = terrainFace,
                loop = true,
                modes = {
                    {
                        key = _groundFacesFillKey,
                        type = 'FILL',
                    },
                    -- {
                    --     key = groundFacesStrokeOuterKey,
                    --     type = 'STROKE_OUTER',
                    -- }
                }
            }
        )
        table.insert(
            result.terrainAlignmentLists,
            {
                faces =  { terrainFace },
                optional = true,
                slopeHigh = constants.slopeHigh,
                slopeLow = constants.slopeLow,
                type = 'EQUAL',
            }
        )
    end,
}

return {
    eras = constants.eras,
    getEraPrefix = function(params, nTerminal, nTrackEdge)
        local _terminalData = params.terminals[nTerminal]
        return privateFuncs.getEraPrefix(params, nTerminal, _terminalData, nTrackEdge)
    end,
    getEraPrefix2 = function(params, nTerminal, terminalData, nTrackEdge)
        return privateFuncs.getEraPrefix(params, nTerminal, terminalData, nTrackEdge)
    end,
    getFromVariant_FlatAreaHeight = function(variant, isFlush)
        return privateFuncs.getFromVariant_FlatAreaHeight(variant, isFlush)
    end,
    getGroundFace = function(face, key)
        return {
            face = face, -- LOLLO NOTE Z is ignored here
            loop = true,
            modes = {
                {
                    type = 'FILL',
                    key = key
                }
            }
        }
    end,
    getGroundFacesFillKey_cargo = function(result, nTerminal, eraPrefix)
        return privateFuncs.getGroundFacesFillKey_cargo(result, nTerminal, eraPrefix)
    end,
    getIsEndFillerEvery3 = function(nTrackEdge)
        return privateFuncs.getIsEndFillerEvery3(nTrackEdge)
    end,
    getTerrainAlignmentList = function(face, raiseBy, alignmentType, slopeHigh, slopeLow)
        if type(raiseBy) ~= 'number' then raiseBy = 0 end
        if stringUtils.isNullOrEmptyString(alignmentType) then alignmentType = 'EQUAL' end -- GREATER, LESS
        if type(slopeHigh) ~= 'number' then slopeHigh = constants.slopeHigh end
        if type(slopeLow) ~= 'number' then slopeLow = constants.slopeLow end
        -- With “EQUAL” the terrain is aligned exactly to the specified faces,
        -- with “LESS” only higher areas are taken down,
        -- with “GREATER” areas below the faces will be filled up.
        -- local raiseBy = 0 -- 0.28 -- a lil bit less than 0.3 to avoid bits of construction being covered by earth
        local raisedFace = {}
        for i = 1, #face do
            raisedFace[i] = face[i]
            raisedFace[i][3] = raisedFace[i][3] + raiseBy
        end
        -- logger.print('LOLLO raisedFaces =') logger.debugPrint(raisedFace)
        return {
            faces = {raisedFace},
            optional = true,
            slopeHigh = slopeHigh,
            slopeLow = slopeLow,
            type = alignmentType,
        }
    end,
    getTerminalDecoTransf = function(posTanX2)
        -- logger.print('getTerminalDecoTransf starting, posTanX2 =') logger.debugPrint(posTanX2)
        local pos1 = posTanX2[1][1]
        local pos2 = posTanX2[2][1]

        local sinZ = (pos2[2] - pos1[2])
        local cosZ = (pos2[1] - pos1[1])
        local length = math.sqrt(sinZ * sinZ + cosZ * cosZ)
        sinZ, cosZ = sinZ / length, cosZ / length

        return {
            cosZ, sinZ, 0, 0,
            -sinZ, cosZ, 0, 0,
            0, 0, 1, 0,
            pos1[1], pos1[2], pos1[3], 1
        }
    end,
    getPlatformObjectTransf_AlwaysVertical = function(posTanX2)
        return privateFuncs.getPlatformObjectTransf_AlwaysVertical(posTanX2)
    end,
    getPlatformObjectTransf_WithYRotation = function(posTanX2) --, angleYFactor)
        return privateFuncs.getPlatformObjectTransf_WithYRotation(posTanX2)
    end,
    getZShiftFor0mPlatform = function (result, nTerminal)
        return privateFuncs.getZShiftFor0mPlatform(result, nTerminal)
    end,
    cargoShelves = {
        doCargoShelf = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge,
            bracket5ModelId, bracket10ModelId, bracket20ModelId,
            legs5ModelId, legs10ModelId, legs20ModelId)

            local isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
            local transfXZoom = isTrackOnPlatformLeft and -1 or 1
            local transfYZoom = isTrackOnPlatformLeft and -1 or 1
            local isEndFiller = privateFuncs.getIsEndFillerEvery3(nTrackEdge)

            local _i1 = isEndFiller and nTrackEdge or (nTrackEdge - 1)
            local _iMax = isEndFiller and nTrackEdge or (nTrackEdge + 1)
            local _cpfs = terminalData.centrePlatformsFineRelative
            local _laneZ = result.laneZs[nTerminal]
            local _zShift = _laneZ - constants.defaultPlatformHeight + privateFuncs.getZShiftFor0mPlatform(result, nTerminal)
            for ii = 1, #_cpfs, privateConstants.cargoShelves.bracketStep do
                local cpf = _cpfs[ii]
                local leadingIndex = cpf.leadingIndex
                if leadingIndex > _iMax then break end
                if leadingIndex >= _i1 then
                    if cpf.type == 0 then -- ground
                        local platformWidth = cpf.width
                        local bracketModelId = bracket5ModelId
                        if platformWidth > 10 then bracketModelId = bracket20ModelId
                        elseif platformWidth > 5 then bracketModelId = bracket10ModelId
                        end
                        result.models[#result.models+1] = {
                            id = bracketModelId,
                            -- transf = transfUtilsUG.mul(
                            --     privateFuncs.getPlatformObjectTransf_WithYRotation(cpf.posTanX2),
                            --     { transfXZoom, 0, 0, 0,  0, transfYZoom, 0, 0,  0, 0, 1, 0,  0, 0, constants.platformRoofZ, 1 }
                            -- ),
                            transf = transfUtils.getTransf_Scaled_Shifted(
                                privateFuncs.getPlatformObjectTransf_WithYRotation(cpf.posTanX2),
                                {transfXZoom, transfYZoom, 1},
                                {0, 0, constants.platformRoofZ + _zShift}
                            ),
                            tag = tag
                        }
                        -- waiting areas on shelves
                        -- we shift it by 2 so it does not cover light and speakers
                        if math.fmod(ii + 2, privateConstants.cargoShelves.pillarPeriod) == 0 then
                            local legsModelId = legs5ModelId
                            local waitingAreaModelId = 'lollo_freestyle_train_station/cargo_waiting_area_on_shelf_5m.mdl'
                            if platformWidth > 10 then
                                legsModelId = legs20ModelId
                                waitingAreaModelId = 'lollo_freestyle_train_station/cargo_waiting_area_on_shelf_20m.mdl'
                            elseif platformWidth > 5 then
                                legsModelId = legs10ModelId
                                waitingAreaModelId = 'lollo_freestyle_train_station/cargo_waiting_area_on_shelf_10m.mdl'
                            end

                            -- local myTransf = transfUtilsUG.mul(
                            --     privateFuncs.getPlatformObjectTransf_AlwaysVertical(cpf.posTanX2),
                            --     { transfXZoom, 0, 0, 0,  0, transfYZoom, 0, 0,  0, 0, 1, 0,  0, 0, constants.platformRoofZ, 1 }
                            -- )
                            local myTransf = transfUtils.getTransf_Scaled_Shifted(
                                privateFuncs.getPlatformObjectTransf_AlwaysVertical(cpf.posTanX2),
                                {transfXZoom, transfYZoom, 1},
                                {0, 0, constants.platformRoofZ + _zShift}
                            )
                            result.models[#result.models+1] = {
                                id = legsModelId,
                                transf = myTransf,
                                tag = tag,
                            }
                            result.models[#result.models+1] = {
                                id = waitingAreaModelId,
                                transf = myTransf,
                                tag = slotHelpers.mangleModelTag(nTerminal, true),
                            }
                        end
                    end
                end
            end
        end,
    },
    deco = {
        getFromVariant_0_or_1 = function(variant)
            return privateFuncs.getFromVariant_0_or_1(variant)
        end,
        getPreviewIcon = function(params)
			local variant = (params ~= nil and type(params.variant) == 'number') and params.variant or 0
			local zeroOneOrTwo = privateFuncs.getFromVariant_0_to_1(variant, 3) * 2
            -- logger.print('getPreviewIcon variant = ' .. tostring(variant) .. '; zeroOneOrTwo = ' .. tostring(zeroOneOrTwo))
            local arrowModelId = 'lollo_freestyle_train_station/icon/perpendicular_wall.mdl'
            local arrowModelTransf = {0.5, 0, 0, 0,  0, 0.5, 0, 0,  0, 0, 0.5, 0,  2, 5, 2, 1}
            if zeroOneOrTwo == 1 then
                arrowModelId = 'lollo_freestyle_train_station/icon/1m_thick_wall.mdl'
            elseif zeroOneOrTwo == 2 then
                arrowModelId = 'lollo_freestyle_train_station/icon/2m_thick_wall.mdl'
            end
            return {
                id = arrowModelId,
                transf = arrowModelTransf,
            }
        end,
        getStationSignFineIndexes = function(params, nTerminal, _terminalData)
            return privateFuncs.deco.getStationSignFineIndexes(params, nTerminal, _terminalData)
        end,
        doPlatformRoof = function(result, slotTransf, tag, slotId, params, nTerminal, nTrackEdge,
            ceiling2_5ModelId, ceiling5ModelId, pillar2_5ModelId, pillar5ModelId, alternativeCeiling2_5ModelId, alternativeCeiling5ModelId, isTunnelOk)
            -- LOLLO NOTE
            -- In every cpf, xZoom needs to grow to 1.06 for 5m platforms and 1.03 for 2.5m platforms,
            -- or even higher, to avoid holes.
            -- The bend direction does not matter coz roofs are centered on cpf by construction.
            -- Straight bits do not get this, to prevent mini glitches linked to roof edges overlapping.
            -- A curvy bit looks like
            -- posTanX2 = {
            --     {
            --       { 74.618930516671, -88.926375041206, -4.9961046930325, },
            --       { 0.90736612885754, 0.41917300105761, -0.031316184097685, },
            --     },
            --     {
            --       { 75.51871658098, -88.501071479124, -5.0269231771651, },
            --       { 0.89988157866202, 0.43506088272462, -0.030580593644242, },
            --     },
            --   },
            -- or
            -- posTanX2 = {
            --     {
            --       { 75.51871658098, -88.501071479124, -5.0269231771651, },
            --       { 0.89988157866202, 0.43506088272462, -0.030580593644242, },
            --     },
            --     {
            --       { 76.412225809289, -88.05935427218, -5.0570392340728, },
            --       { 0.89211113597398, 0.45083114383442, -0.029816116785429, },
            --     },
            --   },
            -- A straightish bit looks like
            -- posTanX2 = {
            --     {
            --       { 91.189691606841, 25.450743870049, -2.4291994686295, },
            --       { -0.84243349866338, 0.53434102600061, 0.069177079024722, },
            --     },
            --     {
            --       { 90.31703601565, 25.996040985237, -2.3569855705537, },
            --       { -0.84945713464798, 0.5228807240266, 0.070840135778156, },
            --     },
            --   },
            -- A straight bit looks like
            -- posTanX2 = {
            --     {
            --       { 70.709585599846, 37.930313278609, -0.71223737503918, },
            --       { -0.85204926314401, 0.51855870913001, 0.071476698029324, },
            --     },
            --     {
            --       { 69.857536015662, 38.448872150194, -0.64076065204387, },
            --       { -0.85204929311475, 0.51855866008981, 0.071476696541689, },
            --     },
            --   },
            -- By construction, all bits are 1m long, except the very first or very last of a platform, which could be shorter.
            -- This is set in constants.fineSegmentLength, which is 1.
            -- posTanX2[*][2][2] is dy/dl
            -- (posTanX2[1][2][2] - posTanX2[2][2][2]) / 1 is Dy/Dl, and it is proportional to the extra arc length for small angles;
            -- these are all small angles by construction, so posTanX2[1][2][2] - posTanX2[2][2][2] is proportional to the extra arc length.
            -- We still need to find a correction factor; checking the data:
            -- abs(posTanX2[1][2][2] - posTanX2[2][2][2]) == 0.0 -> totalStretchFactor == 1.0
            -- abs(posTanX2[1][2][2] - posTanX2[2][2][2]) == 0.015 -> totalStretchFactor == 1.05
            -- => totalStretchFactor = abs(posTanX2[1][2][2] - posTanX2[2][2][2]) * 0.05 / 0.015 / 5 * platformWidth + 1
            -- => totalStretchFactor = abs(posTanX2[1][2][2] - posTanX2[2][2][2]) * 0.66667 * platformWidth + 1
            -- Season 0.6667 to taste, it's empyrical.
            -- In real life I don't know how x and y are orientated, so I must account for both, and also z could give surprises if I have a hump.
            local _modules = params.modules
            local _terminalData = params.terminals[nTerminal]
            local _cpfs = _terminalData.centrePlatformsFineRelative
            local _laneZ = result.laneZs[nTerminal]
            local _zShift = _laneZ - constants.defaultPlatformHeight

            local isTrackOnPlatformLeft = _terminalData.isTrackOnPlatformLeft
            local transfXZoom = isTrackOnPlatformLeft and -1 or 1
            local transfYZoom = isTrackOnPlatformLeft and -1 or 1
            local isEndFiller = privateFuncs.getIsEndFillerEvery3(nTrackEdge)

            local _barredNumberSignIIs = privateFuncs.deco.getStationSignFineIndexes(params, nTerminal, _terminalData)

            local _i1 = isEndFiller and nTrackEdge or (nTrackEdge - 1)
            local _iMax = isEndFiller and nTrackEdge or (nTrackEdge + 1)
            local isFreeFromOpenStairsLeft = {}
            local isFreeFromOpenStairsRight = {}
            for i = _i1, _iMax, 1 do
                isFreeFromOpenStairsLeft[i] = not(_modules[result.mangleId(nTerminal, i+1, constants.idBases.openStairsUpLeftSlotId)])
                isFreeFromOpenStairsRight[i] = (i < 2 or not(_modules[result.mangleId(nTerminal, i-1, constants.idBases.openStairsUpRightSlotId)]))
            end

            local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, 1)
            local perronNumberModelId = 'lollo_freestyle_train_station/roofs/era_c_perron_number_hanging.mdl'
            if eraPrefix == constants.eras.era_a.prefix then perronNumberModelId = 'lollo_freestyle_train_station/roofs/era_a_perron_number_hanging.mdl'
            elseif eraPrefix == constants.eras.era_b.prefix then perronNumberModelId = 'lollo_freestyle_train_station/roofs/era_b_perron_number_hanging_plain.mdl'
            end

            for ii = 1, #_cpfs, privateConstants.deco.ceilingStep do
                local cpf = _cpfs[ii]
                local leadingIndex = cpf.leadingIndex
                if leadingIndex > _iMax then break end
                if leadingIndex >= _i1 then
                    if isTunnelOk or cpf.type ~= 2 then -- ground or bridge
                        local platformWidth = cpf.width
                        local isFreeFromOpenStairsAndTunnels = isFreeFromOpenStairsLeft[leadingIndex] and isFreeFromOpenStairsRight[leadingIndex] and cpf.type ~= 2
                        local roofModelId = isFreeFromOpenStairsAndTunnels
                            and (platformWidth < 5 and ceiling2_5ModelId or ceiling5ModelId)
                            or (platformWidth < 5 and alternativeCeiling2_5ModelId or alternativeCeiling5ModelId)
                        if roofModelId ~= nil then
                            local dx_dl = cpf.posTanX2[2][2][1] - cpf.posTanX2[1][2][1]
                            local dy_dl = cpf.posTanX2[2][2][2] - cpf.posTanX2[1][2][2]
                            local dz_dl = cpf.posTanX2[2][2][3] - cpf.posTanX2[1][2][3]
                            -- local dz = cpf.posTanX2[2][1][3] - cpf.posTanX2[1][1][3]
                            local tr1 = transfXZoom * (
                                1
                                + math.abs(dx_dl) * platformWidth -- account for z rotations, * 1 is an experimental coefficient
                                + math.abs(dy_dl) * platformWidth -- account for z rotations, * 1 is an experimental coefficient
                                - dz_dl * 4 -- account for xy rotations (humps or pits), all roofs are about 5m high, this can be negative
                                -- + math.abs(dz) * 0.1 -- account for extra length due to slope
                            )
                            -- this is a bit slower and a bit more accurate
                            -- local tr1 = transfXZoom * (
                            --     1
                            --     + math.sqrt(dx_dl * dx_dl + dy_dl * dy_dl) * platformWidth -- account for z rotations, * 1 is an experimental coefficient
                            --     - dz_dl * 4 -- account for xy rotations (humps or pits), all roofs are about 5m high, this can be negative
                            -- --     + math.sqrt(dz * dz + 1) -1 -- account for extra length due to slope
                            -- )

                            -- no skew
                            local roofTransf = transfUtils.getTransf_Scaled_Shifted(
                                privateFuncs.getPlatformObjectTransf_WithYRotation(cpf.posTanX2),
                                {tr1, transfYZoom, 1},
                                {0, 0, constants.platformRoofZ + _zShift}
                            )
                            result.models[#result.models+1] = {
                                id = roofModelId,
                                transf = roofTransf,
                                tag = tag
                            }

                            -- yes skew -- this is correct but there are glitches inside bends, because x0-x1 is the same left and right
                            -- local roofTransf = transfUtils.getTransf_Scaled_Shifted(
                            --     privateFuncs.getPlatformObjectTransf_AlwaysVertical(cpf.posTanX2),
                            --     {tr1, transfYZoom, 1},
                            --     {0, 0, constants.platformRoofZ + _zShift}
                            -- )
                            -- local skew = (cpf.posTanX2[2][1][3] - cpf.posTanX2[1][1][3]) * tr1
                            -- result.models[#result.models+1] = {
                            --     id = roofModelId,
                            --     transf = transfUtils.getTransf_XSkewedOnZ(roofTransf, skew),
                            --     tag = tag
                            -- }

                            if cpf.type ~= 2 and isFreeFromOpenStairsAndTunnels and math.fmod(ii, privateConstants.deco.pillarPeriod) == 0 then
                                local pillarTransf = transfUtils.getTransf_Scaled_Shifted(
                                    privateFuncs.getPlatformObjectTransf_AlwaysVertical(cpf.posTanX2),
                                    {transfXZoom, transfYZoom, 1},
                                    {0, 0, constants.platformRoofZ + _zShift}
                                )
                                result.models[#result.models+1] = {
                                    id = platformWidth < 5 and pillar2_5ModelId or pillar5ModelId,
                                    transf = pillarTransf,
                                    tag = tag,
                                }
                                -- prevent overlapping with station name signs
                                if not(_barredNumberSignIIs[ii])
                                and not(_barredNumberSignIIs[ii+1])
                                and (ii == 1 or not(_barredNumberSignIIs[ii-1]))
                                then
                                    if math.fmod(ii, privateConstants.deco.numberSignPeriod) == 0 then
                                        -- local yShift = isTrackOnPlatformLeft and platformWidth * 0.5 - 0.05 or -platformWidth * 0.5 + 0.05
                                        local yShift = -platformWidth * 0.5 + 0.20
                                        result.models[#result.models + 1] = {
                                            id = perronNumberModelId,
                                            slotId = slotId,
                                            -- transf = transfUtilsUG.mul(
                                            --     myTransf,
                                            --     { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, yShift, 4.83, 1 }
                                            -- ),
                                            transf = transfUtils.getTransf_Shifted(pillarTransf, {0, yShift, 4.83}),
                                            tag = tag
                                        }
                                        -- the model index must be in base 0 !
                                        result.labelText[#result.models - 1] = { tostring(nTerminal), tostring(nTerminal)}
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end,
        doAxialWall = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge, wallModelId)
            local _modules = params.modules
            local _cps = terminalData.centrePlatformsRelative
            local _cpl = _cps[nTrackEdge]
            if _cpl.type == 2 then return end -- no walls in tunnels

            local _eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, terminalData, 1)
            local _isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
            local _zShift = 0
            local _laneZ = result.laneZs[nTerminal]
            local wallBaseModelId = (_laneZ == constants.platformHeights._0cm.aboveGround) and privateFuncs.deco.getWallBaseModelId(params, _eraPrefix) or nil

            local isFreeFromFlatAreas = false
            local occupiedWidth = 0
            local occupiedInfo4AxialAreas = result.getOccupiedInfo4AxialAreas(nTerminal, nTrackEdge)
            logger.print('occupiedInfo4AxialAreas =') logger.debugPrint(occupiedInfo4AxialAreas)
            isFreeFromFlatAreas = (occupiedInfo4AxialAreas == nil)
            if not(isFreeFromFlatAreas) then
                occupiedWidth = occupiedInfo4AxialAreas.widthOnOwnTerminalHead
            end
            logger.print('occupiedWidth =', tostring(occupiedWidth))

            local _getSlopedAreaWidth = function(cpl)
                local slopedAreaWidth = result.getOccupiedInfo4SlopedAreas(nTerminal, nTrackEdge).width
                if not(privateFuncs.slopedAreas.isSlopedAreaAllowed(cpl, slopedAreaWidth)) then slopedAreaWidth = 0 end
                return slopedAreaWidth
            end
            local slopedAreaWidth = _getSlopedAreaWidth(_cps[nTrackEdge])
            logger.print('slopedAreaWidth =', tostring(slopedAreaWidth))
            local platformWidth = _cps[nTrackEdge].width
            logger.print('platformWidth =', tostring(platformWidth))

            local leftRightDistance = 0
            local leftTransf = transfUtils.getTransf_ZRotatedM90(slotTransf)
            if (nTrackEdge == 1 and not(_isTrackOnPlatformLeft)) or (nTrackEdge ~= 1 and _isTrackOnPlatformLeft) then
                if isFreeFromFlatAreas then
                    leftTransf = transfUtils.getTransf_Shifted(leftTransf, {-5 + 0.5, 0, _zShift})
                    leftRightDistance = 5 + platformWidth + slopedAreaWidth
                else
                    leftTransf = transfUtils.getTransf_Shifted(leftTransf, {-5 + 0.5 + occupiedWidth, 0, _zShift})
                    leftRightDistance = 5 + platformWidth + slopedAreaWidth - occupiedWidth
                end
            else
                leftTransf = transfUtils.getTransf_Shifted(leftTransf, {-platformWidth -slopedAreaWidth + 0.5, 0, _zShift})
                if isFreeFromFlatAreas then
                    leftRightDistance = 5 + platformWidth + slopedAreaWidth
                else
                    leftRightDistance = 5 + platformWidth + slopedAreaWidth - occupiedWidth
                end
            end
            if leftRightDistance <= 0 then return end

            for k = 1, math.floor(leftRightDistance) do
                result.models[#result.models+1] = {
                    id = wallModelId,
                    tag = tag,
                    transf = leftTransf,
                }
                if wallBaseModelId ~= nil and _cpl.type == 0 then -- only on ground
                    result.models[#result.models+1] = {
                        id = wallBaseModelId,
                        tag = tag,
                        transf = leftTransf,
                    }
                end
                leftTransf = transfUtils.getTransf_XShifted(leftTransf, 1)
            end
            -- close the last bit - remember walls are always 1m wide
            local leftover = leftRightDistance - math.floor(leftRightDistance)
            if leftover > 0.05 then
                leftTransf = transfUtils.getTransf_XShifted(leftTransf, -leftover)
                result.models[#result.models+1] = {
                    id = wallModelId,
                    tag = tag,
                    transf = leftTransf,
                }
                if wallBaseModelId ~= nil and _cpl.type == 0 then -- only on ground
                    result.models[#result.models+1] = {
                        id = wallBaseModelId,
                        tag = tag,
                        transf = leftTransf,
                    }
                end
            end
        end,
        doPlatformWall = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge,
            wall_tunnel_ModelId,
            wall_outside_tunnel_5m_ModelId,
            pillar2_5ModelId, pillar5ModelId,
            isTunnelOk, isSkipAxial
        )
            local _modules = params.modules
            local _cpfs = terminalData.centrePlatformsFineRelative
            local _eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, terminalData, 1)
            local _isSkipPillars = terminalData.isCargo or pillar2_5ModelId == nil or pillar5ModelId == nil
            local _isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
            local _transfXZoom = _isTrackOnPlatformLeft and -1 or 1
            local _transfYZoom = _isTrackOnPlatformLeft and -1 or 1
            local _isEndFiller = privateFuncs.getIsEndFillerEvery3(nTrackEdge)
            -- logger.print('_isEndFiller =', _isEndFiller)
            local _laneZ = result.laneZs[nTerminal]
            local _zShift = _laneZ - constants.defaultPlatformHeight

            -- local _isVertical = false
            local wallBaseModelId = (_laneZ == constants.platformHeights._0cm.aboveGround) and privateFuncs.deco.getWallBaseModelId(params, _eraPrefix) or nil
            local wallBehindModelId
            local _wallThickness = privateFuncs.deco.getMNAdjustedValue_0_To_2_Cycling(params, slotId) -- 0, 1, 2
            if (_wallThickness == 1) then
                wallBehindModelId = privateFuncs.deco.getWallBehindModelId(wall_outside_tunnel_5m_ModelId, false)
            elseif (_wallThickness == 2) then
                wallBehindModelId = privateFuncs.deco.getWallBehindModelId(wall_outside_tunnel_5m_ModelId, true)
            end
            local wallBehindBaseModelId = privateFuncs.deco.getWallBehindBaseModelId(params, _eraPrefix, _wallThickness == 2)

            local perronNumberModelId = 'lollo_freestyle_train_station/roofs/era_c_perron_number_hanging.mdl'
            if _eraPrefix == constants.eras.era_a.prefix then perronNumberModelId = 'lollo_freestyle_train_station/roofs/era_a_perron_number_hanging.mdl'
            elseif _eraPrefix == constants.eras.era_b.prefix then perronNumberModelId = 'lollo_freestyle_train_station/roofs/era_b_perron_number_hanging_plain.mdl'
            end

            local _barredNumberSignIIs = privateFuncs.deco.getStationSignFineIndexes(params, nTerminal, terminalData)

            local _i1 = _isEndFiller and nTrackEdge or (nTrackEdge - 1)
            local _iMax = _isEndFiller and nTrackEdge or (nTrackEdge + 1)

            local isFreeFromOpenStairsLeft = {}
            local isFreeFromOpenStairsRight = {}
            for i = _i1, _iMax, 1 do
                isFreeFromOpenStairsLeft[i] = not(_modules[result.mangleId(nTerminal, i+1, constants.idBases.openStairsUpLeftSlotId)])
                isFreeFromOpenStairsRight[i] = (i < 2 or not(_modules[result.mangleId(nTerminal, i-1, constants.idBases.openStairsUpRightSlotId)]))
            end

            local isFreeFromRoof = not(_modules[result.mangleId(nTerminal, nTrackEdge, constants.idBases.platformRoofSlotId)])

            -- flat areas and deco are shifted by this amount, and it makes sense this way, so we must account for it
            local _deco2FlatAreaShiftInt = math.floor(constants.maxPassengerWaitingAreaEdgeLength / 2)
            local isFreeFromFlatAreas = {}
            local isLookAhead = {}
            for i = _i1, _iMax + 1, 1 do -- look ahead one more bit because of the shift
                local occupiedInfo4FlatAreas = result.getOccupiedInfo4FlatAreas(nTerminal, i)
                isFreeFromFlatAreas[i] = occupiedInfo4FlatAreas == nil
                isLookAhead[i] = occupiedInfo4FlatAreas == nil or not(occupiedInfo4FlatAreas.isEven)
            end
            -- logger.print('*** isFreeFromFlatAreas =') logger.debugPrint(isFreeFromFlatAreas)
            local _getWidthAbove_0m_BarePlatformWidth = function(cpf)
                local slopedAreaWidth = result.getOccupiedInfo4SlopedAreas(nTerminal, cpf.leadingIndex).width
                if not(privateFuncs.slopedAreas.isSlopedAreaAllowed(cpf, slopedAreaWidth)) then slopedAreaWidth = 0 end
                return cpf.width * 0.5 + slopedAreaWidth, slopedAreaWidth -- slotTransf is centred at half platform width + full sloped area width
            end

            local _iiMax = #_cpfs
            -- logger.print('############')
            for ii = 1, _iiMax, privateConstants.deco.ceilingStep do
                local cpf = _cpfs[ii]
                local leadingIndex = cpf.leadingIndex
                if leadingIndex > _iMax then break end
                if leadingIndex >= _i1 then
                    if isTunnelOk or cpf.type ~= 2 then -- ground or bridge, tunnel only if allowed
                        local isCanDraw = false -- are there stations or exits in this fine segment?
                        if isLookAhead[cpf.leadingIndex] then
                            local cpfAheadByDeco2FlatAreaShift = _cpfs[ii + _deco2FlatAreaShiftInt]
                            isCanDraw = not(cpfAheadByDeco2FlatAreaShift)
                                or isFreeFromFlatAreas[cpfAheadByDeco2FlatAreaShift.leadingIndex]
                                or not(isLookAhead[cpfAheadByDeco2FlatAreaShift.leadingIndex])
                            -- logger.print('platform wall acting on a shifted flat area, nTerminal = ' .. nTerminal)
                        else
                            isCanDraw = isFreeFromFlatAreas[cpf.leadingIndex]
                            -- logger.print('platform wall acting on a non-shifted flat area, nTerminal = ' .. nTerminal)
                        end
                        if isCanDraw then
                            -- tunnels: do not raise the walls or they may cut through the ceiling. On second thoughts, I'll leave it as it is for now.
                            local widthAboveNil, slopedAreaWidth = _getWidthAbove_0m_BarePlatformWidth(cpf)
                            -- this would help if I take cpf.posTanX2, but then I'd get some ugly steps.
                            -- local yShift = _isTrackOnPlatformLeft and -cpf.width * 0.5 - slopedAreaWidth or cpf.width * 0.5 + slopedAreaWidth

                            local wallPosTanX2, xRatio, yRatio = transfUtils.getParallelSideways(
                                cpf.posTanX2,
                                (_isTrackOnPlatformLeft and -widthAboveNil or widthAboveNil)
                            )

                            -- we should divide the following by the models length, but it is always 1, as set in the meshes
                            -- local xScaleFactor = transfUtils.getPositionsDistance_onlyXY(wallPosTanX2[1][1], wallPosTanX2[2][1])
                            local xScaleFactor = xRatio
                            local wallTransf = transfUtils.getTransf_Scaled_Shifted(
                                privateFuncs.getPlatformObjectTransf_AlwaysVertical(wallPosTanX2),
                                {_transfXZoom * xScaleFactor, _transfYZoom, 1},
                                {0, 0, _laneZ}
                            )
                            local skew = wallPosTanX2[2][1][3] - wallPosTanX2[1][1][3]
                            if _isTrackOnPlatformLeft then skew = -skew end
                            wallTransf = transfUtils.getTransf_XSkewedOnZ(wallTransf, skew)
                            local wallModelId = cpf.type == 2 and wall_tunnel_ModelId or wall_outside_tunnel_5m_ModelId
                            result.models[#result.models+1] = {
                                id = wallModelId,
                                tag = tag,
                                transf = wallTransf,
                            }
                            if wallBaseModelId ~= nil and cpf.type == 0 then -- only on ground
                                result.models[#result.models+1] = {
                                    id = wallBaseModelId,
                                    tag = tag,
                                    transf = wallTransf,
                                }
                            end

                            if wallBehindModelId ~= nil and cpf.type == 0 then -- only on ground
                                privateFuncs.deco.addWallBehind(result, tag, wallBehindBaseModelId, wallBehindModelId, wallTransf, widthAboveNil, xScaleFactor, _eraPrefix, _laneZ)
                            end

                            -- extend wall along platform head extensions
                            local howMany1mChunks = nil
                            local headWallPosTanX2 = nil
                            local headTransfXZoom, headTransfYZoom = _transfXZoom, _transfYZoom
                            if ii == 1 then
                                local platformHeadModule = _modules[result.mangleId(nTerminal, 1, constants.idBases.platformHeadSlotId)]
                                if platformHeadModule ~= nil then
                                    howMany1mChunks = platformHeadModule.metadata.howMany4mChunks * 4
                                    headWallPosTanX2 = transfUtils.getPosTanX2Reversed(wallPosTanX2)
                                    -- here, the wall is inside out
                                    headTransfXZoom = -headTransfXZoom
                                    headTransfYZoom = -headTransfYZoom
                                end
                            elseif ii == _iiMax then
                                local platformHeadModule = _modules[result.mangleId(nTerminal, cpf.leadingIndex, constants.idBases.platformHeadSlotId)]
                                if platformHeadModule ~= nil then
                                    howMany1mChunks = platformHeadModule.metadata.howMany4mChunks * 4
                                    headWallPosTanX2 = arrayUtils.cloneDeepOmittingFields(wallPosTanX2)
                                end
                            end
                            if howMany1mChunks ~= nil then
                                local headWallxScaleFactor = 1 --xRatio
                                -- headTransfXZoom and headTransfYZoom are -1 or 1
                                for hh = 1, howMany1mChunks do
                                    headWallPosTanX2 = transfUtils.getExtrapolatedPosTanX2Continuation(headWallPosTanX2, 1)
                                    local headWallSkew = headWallPosTanX2[2][1][3] - headWallPosTanX2[1][1][3]
                                    if _isTrackOnPlatformLeft then headWallSkew = -headWallSkew end
                                    if ii == 1 then headWallSkew = -headWallSkew end
                                    local platformHeadExtensionTransf = transfUtils.getTransf_XSkewedOnZ(
                                        transfUtils.getTransf_Scaled_Shifted(
                                            privateFuncs.getPlatformObjectTransf_AlwaysVertical(headWallPosTanX2),
                                            {headTransfXZoom * headWallxScaleFactor, headTransfYZoom, 1},
                                            {0, 0, _laneZ}
                                        ),
                                        headWallSkew
                                    )
                                    result.models[#result.models+1] = {
                                        id = wallModelId,
                                        tag = tag,
                                        transf = platformHeadExtensionTransf,
                                    }
                                    if wallBaseModelId ~= nil and cpf.type == 0 then -- only on ground
                                        result.models[#result.models+1] = {
                                            id = wallBaseModelId,
                                            tag = tag,
                                            transf = platformHeadExtensionTransf,
                                        }
                                    end
                                    if wallBehindModelId ~= nil and cpf.type == 0 then -- only on ground
                                        privateFuncs.deco.addWallBehind(result, tag, wallBehindBaseModelId, wallBehindModelId, platformHeadExtensionTransf, widthAboveNil, xScaleFactor, _eraPrefix, _laneZ)
                                    end
                                end
                            end

                            -- if ii % 4 == 0 then
                            --     result.models[#result.models+1] = {
                            --         id = 'lollo_freestyle_train_station/icon/blue.mdl',
                            --         transf = wallTransf,
                            --         tag = tag
                            --     }
                            -- end

                            -- add pillars
                            if cpf.type ~= 2
                            and not(_isSkipPillars)
                            and isFreeFromOpenStairsLeft[leadingIndex] and isFreeFromOpenStairsRight[leadingIndex]
                            and math.fmod(ii, privateConstants.deco.numberSignPeriod) == 0
                            -- no platform numbers if there is a roof
                            and isFreeFromRoof
                            -- prevent overlapping with station name signs
                            and not(_barredNumberSignIIs[ii])
                            and not(_barredNumberSignIIs[ii+1])
                            and (ii == 1 or not(_barredNumberSignIIs[ii-1]))
                            then
                                local yShift4Pillar = _isTrackOnPlatformLeft and (0.1 + cpf.width * 0.5) or (-0.1 - cpf.width * 0.5) -- wall models are shifted by 2.5m
                                -- local pillarTransf = transfUtilsUG.mul(
                                --     privateFuncs.getPlatformObjectTransf_AlwaysVertical(wallPosTanX2),
                                --     {
                                --         _transfXZoom, 0, 0, 0,
                                --         0, _transfYZoom, 0, 0,
                                --         0, 0, 1, 0,
                                --         0, yShift4Pillar, constants.platformRoofZ, 1
                                --     }
                                -- )
                                local pillarTransf = transfUtils.getTransf_Scaled_Shifted(
                                    privateFuncs.getPlatformObjectTransf_AlwaysVertical(wallPosTanX2),
                                    {_transfXZoom, _transfYZoom, 1},
                                    {0, yShift4Pillar, constants.platformRoofZ + _zShift}
                                )
                                result.models[#result.models+1] = {
                                    id = cpf.width < 5 and pillar2_5ModelId or pillar5ModelId,
                                    transf = pillarTransf,
                                    tag = tag,
                                }

                                local yShift4PerronNumber = -cpf.width * 0.5 + 0.20
                                result.models[#result.models + 1] = {
                                    id = perronNumberModelId,
                                    slotId = slotId,
                                    -- transf = transfUtilsUG.mul(
                                    --     pillarTransf,
                                    --     { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, yShift4PerronNumber, 4.83, 1 }
                                    -- ),
                                    transf = transfUtils.getTransf_Shifted(pillarTransf, {0, yShift4PerronNumber, 4.83}),
                                    tag = tag
                                }
                                -- the model index must be in base 0 !
                                result.labelText[#result.models - 1] = { tostring(nTerminal), tostring(nTerminal)}
                            end

                            -- add walls across
                            if not(isSkipAxial) then
                                if cpf.type ~= 2 then
                                    -- whenever getting in or out of a tunnel, skip altogether
                                    local cpfM1 = ii ~= 1 and _cpfs[ii-1] or nil
                                    local cpfP1 = ii ~= _iiMax and _cpfs[ii+1] or nil
                                    if ii == 1 then
                                        -- skip near platform head
                                        if not(_modules[result.mangleId(nTerminal, 1, constants.idBases.platformHeadSlotId)]) then
                                            if not(result.getOccupiedInfo4AxialAreas(nTerminal, cpf.leadingIndex)) then
                                                -- logger.print('_ONE')
                                                privateFuncs.deco.addWallAcross(cpf, true, result, tag, wallModelId, slopedAreaWidth + cpf.width, _isTrackOnPlatformLeft, wallTransf, ii, _iiMax, wallBaseModelId)
                                            else
                                                -- logger.print('_TWO')
                                                privateFuncs.deco.addWallAcross(cpf, true, result, tag, wallModelId, slopedAreaWidth, _isTrackOnPlatformLeft, wallTransf, ii, _iiMax, wallBaseModelId)
                                            end
                                        end
                                    elseif ii == _iiMax then
                                        -- skip near platform head
                                        if not(_modules[result.mangleId(nTerminal, _cpfs[ii].leadingIndex, constants.idBases.platformHeadSlotId)]) then
                                            if not(result.getOccupiedInfo4AxialAreas(nTerminal, cpf.leadingIndex)) then
                                                -- logger.print('_THREE')
                                                privateFuncs.deco.addWallAcross(cpf, false, result, tag, wallModelId, slopedAreaWidth + cpf.width, _isTrackOnPlatformLeft, wallTransf, ii, _iiMax, wallBaseModelId)
                                            else
                                                -- logger.print('_FOUR')
                                                privateFuncs.deco.addWallAcross(cpf, false, result, tag, wallModelId, slopedAreaWidth, _isTrackOnPlatformLeft, wallTransf, ii, _iiMax, wallBaseModelId)
                                            end
                                        end
                                    elseif leadingIndex ~= cpfM1.leadingIndex then
                                        local deltaY = cpf.width + slopedAreaWidth - cpfM1.width - result.getOccupiedInfo4SlopedAreas(nTerminal, cpfM1.leadingIndex).width
                                            -- logger.print('_FIVE')
                                            privateFuncs.deco.addWallAcross(cpf, true, result, tag, wallModelId, deltaY, _isTrackOnPlatformLeft, wallTransf, ii, _iiMax, wallBaseModelId)
                                    elseif leadingIndex ~= cpfP1.leadingIndex then
                                        local deltaY = cpf.width + slopedAreaWidth - cpfP1.width - result.getOccupiedInfo4SlopedAreas(nTerminal, cpfP1.leadingIndex).width
                                        -- logger.print('_SIX')
                                        privateFuncs.deco.addWallAcross(cpf, false, result, tag, wallModelId, deltaY, _isTrackOnPlatformLeft, wallTransf, ii, _iiMax, wallBaseModelId)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end,
        doTrackWall = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge,
            wall_tunnel_ModelId,
            wall_not_tunnel_5m_ModelId,
            isTunnelOk
        )
            -- centreTracksFineRelative could happen to be nil
            local _ctfs = terminalData.centreTracksFineRelative
            if type(_ctfs) ~= 'table' then return end

            -- do not confuse the tracks array with the platforms array: they are similar but different
            local _eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, terminalData, 1)
            local isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
            local transfXZoom = isTrackOnPlatformLeft and 1 or -1 -- -1 or 1
            local transfYZoom = isTrackOnPlatformLeft and 1 or -1 -- -1 or 1
            local isEndFiller = privateFuncs.getIsEndFillerEvery3(nTrackEdge)
            local _laneZ = result.laneZs[nTerminal]

            -- query the first platform segment coz track segments, unlike platform segments,
            -- have no knowledge of the era: they only have leadingIndex, posTanX2, type and width.
            local wallBaseModelId = privateFuncs.deco.getWallBaseModelId(params, _eraPrefix)
            local wallBehindModelId
            local _wallThickness = privateFuncs.deco.getMNAdjustedValue_0_To_2_Cycling(params, slotId) -- 0, 1, 2
            if (_wallThickness == 1) then
                wallBehindModelId = privateFuncs.deco.getWallBehindModelId(wall_not_tunnel_5m_ModelId, false)
            elseif (_wallThickness == 2) then
                wallBehindModelId = privateFuncs.deco.getWallBehindModelId(wall_not_tunnel_5m_ModelId, true)
            end
            local wallBehindBaseModelId = privateFuncs.deco.getWallBehindBaseModelId(params, _eraPrefix, _wallThickness == 2)

            local _i1 = isEndFiller and nTrackEdge or (nTrackEdge - 1)
            local _iMax = isEndFiller and nTrackEdge or (nTrackEdge + 1)

            for ii = 1, #_ctfs, privateConstants.deco.ceilingStep do
                local ctf = _ctfs[ii]
                local leadingIndex = ctf.leadingIndex
                if leadingIndex > _iMax then break end
                if leadingIndex >= _i1 then
                    if isTunnelOk or ctf.type ~= 2 then -- ground or bridge, tunnel only if allowed
                        -- tunnels: do not raise the walls or they may cut through the ceiling. On second thoughts, I'll leave it as it is for now.
                        local widthAboveNil = ctf.width * 0.5
                        local wallPosTanX2 = transfUtils.getParallelSidewaysCoarse(
                            ctf.posTanX2,
                            (isTrackOnPlatformLeft and widthAboveNil or -widthAboveNil)
                        )
                        -- we should divide the following by the models length, but it is always 1, as set in the mesh
                        local xScaleFactor = transfUtils.getPositionsDistance_onlyXY(wallPosTanX2[1][1], wallPosTanX2[2][1])
                        local wallModelId = ctf.type == 2 and wall_tunnel_ModelId or wall_not_tunnel_5m_ModelId
                        -- local wallTransf = transfUtilsUG.mul(
                        --     privateFuncs.getPlatformObjectTransf_AlwaysVertical(wallPosTanX2),
                        --     {
                        --         transfXZoom * xScaleFactor, 0, 0, 0,
                        --         0, transfYZoom, 0, 0,
                        --         0, 0, 1, 0,
                        --         0, 0, _laneZ, 1
                        --     }
                        -- )
                        local wallTransf = transfUtils.getTransf_Scaled_Shifted(
                            privateFuncs.getPlatformObjectTransf_AlwaysVertical(wallPosTanX2),
                            {transfXZoom * xScaleFactor, transfYZoom, 1},
                            {0, 0, _laneZ}
                        )
                        -- if not(_isVertical) then
                            local skew = wallPosTanX2[2][1][3] - wallPosTanX2[1][1][3]
                            if not(isTrackOnPlatformLeft) then skew = -skew end
                            wallTransf = transfUtils.getTransf_XSkewedOnZ(wallTransf, skew)
                        -- end
                        result.models[#result.models+1] = {
                            id = wallModelId,
                            transf = wallTransf,
                            tag = tag
                        }
                        result.models[#result.models+1] = {
                            id = wallBaseModelId,
                            transf = wallTransf,
                            tag = tag
                        }
                        if wallBehindModelId ~= nil and ctf.type == 0 then -- only on ground
                            privateFuncs.deco.addWallBehind(result, tag, wallBehindBaseModelId, wallBehindModelId, wallTransf, widthAboveNil, xScaleFactor, _eraPrefix, _laneZ)
                        end
                    end
                end
            end
        end,
    },
    edges = {
        addEdges = function(result, tag, params, nTerminal, terminalData)
            logger.print('moduleHelpers.edges.addEdges starting for terminal', nTerminal, ', tag = ', (tag or 'NIL'))
            -- logger.print('result.edgeLists =') logger.debugPrint(result.edgeLists)
    
            local nNodesInTerminalSoFar = 0 -- privateFuncs.edges._getNNodesInTerminalsSoFar(params, nTerminal)
    
            local tag2nodes = {
                [tag] = { } -- list of base 0 indexes
            }
    
            for i = 1, #terminalData.platformEdgeLists + #terminalData.trackEdgeLists do
                for ii = 1, 2 do
                    tag2nodes[tag][#tag2nodes[tag]+1] = nNodesInTerminalSoFar
                    nNodesInTerminalSoFar = nNodesInTerminalSoFar + 1
                end
            end
    
            privateFuncs.edges._addPlatformEdges(result, tag2nodes, params, nTerminal, terminalData)
            privateFuncs.edges._addTrackEdges(result, tag2nodes, params, nTerminal, terminalData)
    
            -- logger.print('build 35716 moduleHelpers.edges.addEdges ending for terminal', nTerminal, ', result.edgeLists =') logger.debugPrint(result.edgeLists)
        end,
        dynamicBridgeTypes_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams)
            -- local sampleUpdateScriptParams = {
            --     bridgeFileName = "stone.lua",
            -- }
			logger.print('dynamicBridgeTypes_updateFn got updateScriptParams =') logger.debugPrint(updateScriptParams)
            if updateScriptParams == nil then return end

			local nTerminal, _, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            if not(result.platformEdgeListsIndexes) or not(result.platformEdgeListsIndexes[nTerminal]) then return end
            if not(result.trackEdgeListsIndexes) or not(result.trackEdgeListsIndexes[nTerminal]) then return end

            local _edgeType = not(stringUtils.isNullOrEmptyString(updateScriptParams.bridgeFileName)) and 'BRIDGE' or nil
            local _updateEdge = function(edgeListsIndex)
                if edgeListsIndex == nil then return end
                if result.edgeLists[edgeListsIndex].edgeType ~= 'BRIDGE' then return end
                -- redundant code to force no bridges if it must be
                result.edgeLists[edgeListsIndex].edgeType = _edgeType
                if _edgeType == nil then
                    result.edgeLists[edgeListsIndex].alignTerrain = true
                else
                    result.edgeLists[edgeListsIndex].edgeTypeName = updateScriptParams.bridgeFileName
                end
            end

            for telIndex, edgeListsIndex in pairs(result.platformEdgeListsIndexes[nTerminal]) do
				-- logger.print('edgeListsIndex =') logger.debugPrint(edgeListsIndex)
                _updateEdge(edgeListsIndex)
			end
			for telIndex, edgeListsIndex in pairs(result.trackEdgeListsIndexes[nTerminal]) do
				-- logger.print('edgeListsIndex =') logger.debugPrint(edgeListsIndex)
                _updateEdge(edgeListsIndex)
				--[[
				if telIndex ~= nil then
					local tel = params.terminals[nTerminal].trackEdgeLists[telIndex]
					print('tel =')
					debugPrint(params.terminals[nTerminal].trackEdgeLists[telIndex].trackTypeName)
					if tel ~= nil then
						params.terminals[nTerminal].trackEdgeLists[telIndex].trackTypeName = 'high_speed.lua'
						print('tel updated') -- this does nothing to the params, there seems to be a deep copy at work
					end
				end
				]]
			end
		end,
        dynamicTrackTypes_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams)
            -- local sampleUpdateScriptParams = {
            --     catenary = false,
            --     trackType = "tgr_thirdRail.lua",
            -- }
			logger.print('dynamicTrackTypes_updateFn got updateScriptParams =') logger.debugPrint(updateScriptParams)
            if updateScriptParams == nil or updateScriptParams.trackType == nil or updateScriptParams.catenary == nil then return end

			local nTerminal, _, baseId = result.demangleId(slotId)
			-- tag = "__module_62010000" if nTerminal is 1
			-- tag = "__module_62020000" if nTerminal is 2
			-- etc
			if not nTerminal or not baseId then return end

            if not(result.trackEdgeListsIndexes) or not(result.trackEdgeListsIndexes[nTerminal]) then return end

			for telIndex, edgeListsIndex in pairs(result.trackEdgeListsIndexes[nTerminal]) do
				-- logger.print('edgeListsIndex =') logger.debugPrint(edgeListsIndex)
				if edgeListsIndex ~= nil then
                    result.edgeLists[edgeListsIndex].params.catenary = updateScriptParams.catenary -- true
					result.edgeLists[edgeListsIndex].params.type = updateScriptParams.trackType -- 'high_speed.lua'
					-- logger.print('high speed module updated a track') logger.debugPrint(result.edgeLists[edgeListsIndex])
				end
				--[[
				if telIndex ~= nil then
					local tel = params.terminals[nTerminal].trackEdgeLists[telIndex]
					print('tel =')
					debugPrint(params.terminals[nTerminal].trackEdgeLists[telIndex].trackTypeName)
					if tel ~= nil then
						params.terminals[nTerminal].trackEdgeLists[telIndex].trackTypeName = 'high_speed.lua'
						print('tel updated') -- this does nothing to the params, there seems to be a deep copy at work
					end
				end
				]]
			end
		end,
        dynamicTunnelTypes_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams)
            -- local sampleUpdateScriptParams = {
            --     tunnelFileName = "tunnel.lua",
            -- }
			logger.print('dynamicTunnelTypes_updateFn got updateScriptParams =') logger.debugPrint(updateScriptParams)
            if updateScriptParams == nil then return end

			local nTerminal, _, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            if not(result.platformEdgeListsIndexes) or not(result.platformEdgeListsIndexes[nTerminal]) then return end
            if not(result.trackEdgeListsIndexes) or not(result.trackEdgeListsIndexes[nTerminal]) then return end

            local _edgeType = not(stringUtils.isNullOrEmptyString(updateScriptParams.tunnelFileName)) and 'TUNNEL' or nil
            local _updateEdge = function(edgeListsIndex)
                if edgeListsIndex == nil then return end
                if result.edgeLists[edgeListsIndex].edgeType ~= 'TUNNEL' then return end
                -- redundant code to force no tunnels if it must be
                result.edgeLists[edgeListsIndex].edgeType = _edgeType
                if _edgeType == nil then
                    result.edgeLists[edgeListsIndex].alignTerrain = true
                else
                    result.edgeLists[edgeListsIndex].edgeTypeName = updateScriptParams.tunnelFileName
                end
            end

            for telIndex, edgeListsIndex in pairs(result.platformEdgeListsIndexes[nTerminal]) do
				-- logger.print('edgeListsIndex =') logger.debugPrint(edgeListsIndex)
                _updateEdge(edgeListsIndex)
			end
			for telIndex, edgeListsIndex in pairs(result.trackEdgeListsIndexes[nTerminal]) do
				-- logger.print('edgeListsIndex =') logger.debugPrint(edgeListsIndex)
                _updateEdge(edgeListsIndex)
				--[[
				if telIndex ~= nil then
					local tel = params.terminals[nTerminal].trackEdgeLists[telIndex]
					print('tel =')
					debugPrint(params.terminals[nTerminal].trackEdgeLists[telIndex].trackTypeName)
					if tel ~= nil then
						params.terminals[nTerminal].trackEdgeLists[telIndex].trackTypeName = 'high_speed.lua'
						print('tel updated') -- this does nothing to the params, there seems to be a deep copy at work
					end
				end
				]]
			end
		end,
    },
    extraStationCapacity = {
        getStationPoolCapacities = function(modules, result)
            local extraCargoCapacity = 0
            local extraPassengersCapacity = 0

            for num, slot in pairs(result.slots) do
                local module = modules[slot.id]
                if module and module.metadata and module.metadata.moreCapacity then
                    if type(module.metadata.moreCapacity.cargo) == 'number' then
                        extraCargoCapacity = extraCargoCapacity + module.metadata.moreCapacity.cargo
                    end
                    if type(module.metadata.moreCapacity.passenger) == 'number' then
                        extraPassengersCapacity = extraPassengersCapacity + module.metadata.moreCapacity.passenger
                    end
                end
            end
            return extraCargoCapacity, extraPassengersCapacity
        end,
    },
    axialAreas = {
        addCargoLaneToSelf = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
            return privateFuncs.axialAreas.addCargoLaneToSelf(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        end,
        addExitPole = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
            return privateFuncs.axialAreas.addExitPole(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        end,
        addPassengerLaneToSelf = function(result, slotTransf, tag, slotId, params, nTerminal, _terminalData, nTrackEdge)
            return privateFuncs.axialAreas.addPassengerLaneToSelf(result, slotTransf, tag, slotId, params, nTerminal, _terminalData, nTrackEdge)
        end,
        exitWithEdgeModule_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams, isSnap, isFake)
            local nTerminal, nTrackEdge, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            local _terminalData = params.terminals[nTerminal]
            local adjustedTransf = privateFuncs.axialAreas.getMNAdjustedTransf(params, slotId, slotTransf)

			local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, nTrackEdge)

			-- local myGroundFacesFillKey = constants[eraPrefix .. 'groundFacesFillKey']
			result.models[#result.models + 1] = {
				id = 'lollo_freestyle_train_station/railroad/axial/passengers/' .. eraPrefix .. 'edge.mdl',
				slotId = slotId,
				transf = adjustedTransf,
				tag = tag
			}
            -- if logger.isExtendedLog() then
                -- if isSnap then
                --     result.models[#result.models + 1] = {
                --         id = 'lollo_freestyle_train_station/icon/red.mdl',
                --         slotId = slotId,
                --         transf = transfUtils.getTransf_XShifted(adjustedTransf, 0.5),
                --         tag = tag
                --     }
                -- else
                --     result.models[#result.models + 1] = {
                --         id = 'lollo_freestyle_train_station/icon/blue.mdl',
                --         slotId = slotId,
                --         transf = transfUtils.getTransf_XShifted(adjustedTransf, 0.5),
                --         tag = tag
                --     }
                -- end
            -- end
            -- LOLLO NOTE
            -- These are invisible walls that should block silly auto snapping,
            -- which the game attempts, fails at and raises an error UG TODO this is wrong
            -- They are useless coz the game still tries to snap together edges,
            -- which belong to the station, ignoring this.
            -- They only work with edges, which do not belong to the station.
            -- result.colliders[#result.colliders+1] = {
            --     params = {
            --         halfExtents = { 10, 0.1, 1, },
            --     },
            --     transf = transfUtils.getTransf_Shifted(adjustedTransf, {1.0, 0.6, 0}), -- halfway into the edge, 0.6 right
            --     type = 'BOX',
            -- }
            -- result.colliders[#result.colliders+1] = {
            --     params = {
            --         halfExtents = { 10, 0.1, 1, },
            --     },
            --     transf = transfUtils.getTransf_Shifted(adjustedTransf, {1.0, -0.6, 0}), -- halfway into the edge, 0.6 left
            --     type = 'BOX',
            -- }
            privateFuncs.axialAreas.addExitPole(result, slotTransf, tag, slotId, params, nTerminal, _terminalData, nTrackEdge)
            privateFuncs.axialAreas.addPassengerLaneToSelf(result, slotTransf, tag, slotId, params, nTerminal, _terminalData, nTrackEdge)

            if not(isFake) then
                local _autoBridgePathsRefData = autoBridgePathsHelper.getData4Era(eraPrefix)
                table.insert(
                    result.edgeLists,
                    {
                        alignTerrain = false, -- only align on ground and in tunnels
                        edges = transfUtils.getPosTanX2Transformed(
                            {
                                { { 0.5, 0, 0 }, { 1, 0, 0 } },  -- node 0 pos, tan
                                { { 1.5, 0, 0 }, { 1, 0, 0 } },  -- node 1 pos, tan
                            },
                            adjustedTransf
                        ),
                        -- better make it a bridge to avoid ugly autolinks between nearby modules
                        edgeType = 'BRIDGE',
                        edgeTypeName = _autoBridgePathsRefData.bridgeTypeName_withRailing,
                        freeNodes = { 1 },
                        params = {
                            hasBus = true,
                            tramTrackType  = 'NO',
                            type = _autoBridgePathsRefData.streetTypeName_noBridge,
                        },
                        snapNodes = isSnap and { 1 } or {},
                        -- tag2nodes = {},
                        tag2nodes = {
                            [tag] = { 0, 1 } -- list of base 0 indexes of nodes
                        },
                        type = 'STREET'
                    }
                )
            end

			local terrainAlignmentList = {
				faces = {
					transfUtils.getFaceTransformed_FAST(
                        adjustedTransf,
                        {
                            {-1, -2, 0, 1},
                            {-1, 2, 0, 1},
                            {1.0, 2, 0, 1},
                            {1.0, -2, 0, 1},
                        }
                    )
				},
				optional = true,
				slopeHigh = constants.slopeHigh,
				slopeLow = constants.slopeLow,
				type = 'LESS',
			}
			result.terrainAlignmentLists[#result.terrainAlignmentLists + 1] = terrainAlignmentList
        end,
        getMNAdjustedTransf = function(params, slotId, slotTransf)
            return privateFuncs.axialAreas.getMNAdjustedTransf(params, slotId, slotTransf)
        end,
        getPreviewIcon = function(params)
			local variant = (params ~= nil and type(params.variant) == 'number') and params.variant or 0
			local tilt, min, max = privateFuncs.getFromVariant_AxialAreaTilt(variant)
			local arrowModelId = 'lollo_freestyle_train_station/icon/arrows_mid_blue.mdl'
			local arrowModelTransf = {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  10, -2, 8, 1}
            if tilt == min then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  10, -2, 9, 1}
            elseif tilt == max then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  10, -2, 7, 1}
			elseif tilt < 0 then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  10, -2, 9, 1}
			elseif tilt > 0 then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  10, -2, 7, 1}
			end
            return {
                id = arrowModelId,
                transf = arrowModelTransf,
            }
        end,
    },
    flatAreas = {
        doTerrain4StationSquare = function(height, slotTransf, result, groundFacesFillKey, groundFacesStrokeOuterKey)
            local groundFace = { -- the ground faces ignore z, the alignment lists don't
                {0, -5.5, height, 1},
                {0, 5.5, height, 1},
                {6.0, 5.5, height, 1},
                {6.0, -5.5, height, 1},
            }
            modulesutil.TransformFaces(slotTransf, groundFace)
            table.insert(
                result.groundFaces,
                {
                    face = groundFace,
                    modes = {
                        {
                            type = 'FILL',
                            key = groundFacesFillKey
                        },
                        {
                            type = 'STROKE_OUTER',
                            key = groundFacesStrokeOuterKey
                        }
                    }
                }
            )
            local terrainAlignmentList = {
                faces = { groundFace },
                optional = true,
                slopeHigh = constants.slopeHigh,
                slopeLow = constants.slopeLow,
                type = 'EQUAL',
            }
            result.terrainAlignmentLists[#result.terrainAlignmentLists + 1] = terrainAlignmentList
        end,
        getFromVariant_0_to_1 = function(variant, nSteps)
            return privateFuncs.getFromVariant_0_to_1(variant, nSteps)
        end,
        getMNAdjustedTransf = function(params, slotId, slotTransf, isFlush)
            return privateFuncs.flatAreas.getMNAdjustedTransf(params, slotId, slotTransf, isFlush)
        end,
        getMNAdjustedValue_0To1_Cycling = function(params, slotId, nSteps)
            local variant = privateFuncs.getVariant(params, slotId)
            return privateFuncs.getFromVariant_0_to_1(variant, nSteps)
        end,
        getPreviewIcon = function(params)
			local variant = (params ~= nil and type(params.variant) == 'number') and params.variant or 0
			local deltaZ, min, max = privateFuncs.getFromVariant_FlatAreaHeight(variant, false)
			local arrowModelId = 'lollo_freestyle_train_station/icon/arrows_mid_blue.mdl'
			local arrowModelTransf = {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  10, -2, 8, 1}
			if deltaZ == min then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  10, -2, 7, 1}
			elseif deltaZ == max then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  10, -2, 9, 1}
            elseif deltaZ < 0 then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  10, -2, 7, 1}
			elseif deltaZ > 0 then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  10, -2, 9, 1}
			end
            return {
                id = arrowModelId,
                transf = arrowModelTransf,
            }
        end,
        addCargoLaneToSelf = function(result, slotAdjustedTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
            return privateFuncs.flatAreas.addCargoLaneToSelf(result, slotAdjustedTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        end,
        addPassengerLaneToSelf = function(result, slotAdjustedTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
            return privateFuncs.flatAreas.addPassengerLaneToSelf(result, slotAdjustedTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        end,

        exitWithEdgeModule_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams, isSnap, isFake)
			local nTerminal, nTrackEdge, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            local _terminalData = params.terminals[nTerminal]
			-- LOLLO NOTE tag looks like '__module_201030', never mind what you write into it, the game overwrites it
			-- in base_config.lua
			-- Set it into the models, so the game knows what module they belong to.

			local zAdjustedTransf = privateFuncs.flatAreas.getMNAdjustedTransf(params, slotId, slotTransf, false)

			local cpl = _terminalData.centrePlatformsRelative[nTrackEdge]
			local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, nTrackEdge)

			-- local myGroundFacesFillKey = constants[eraPrefix .. 'groundFacesFillKey']
			result.models[#result.models + 1] = {
				id = 'lollo_freestyle_train_station/railroad/flatSides/passengers/' .. eraPrefix .. 'stairs_edge.mdl',
				slotId = slotId,
				transf = zAdjustedTransf,
				tag = tag
			}
            privateFuncs.flatAreas.addExitPole(result, slotTransf, tag, slotId, params, nTerminal, _terminalData, nTrackEdge)

			-- this connects the platform to its outer edge (ie border)
			privateFuncs.flatAreas.addPassengerLaneToSelf(result, zAdjustedTransf, tag, slotId, params, nTerminal, _terminalData, nTrackEdge)

            if not(isFake) then
                local _autoBridgePathsRefData = autoBridgePathsHelper.getData4Era(eraPrefix)
                table.insert(
                    result.edgeLists,
                    {
                        alignTerrain = false, -- only align on ground and in tunnels
                        edges = transfUtils.getPosTanX2Transformed(
                            {
                                { { 0.5, 0, 0 }, { 1, 0, 0 } },  -- node 0 pos, tan
                                { { 1.5, 0, 0 }, { 1, 0, 0 } },  -- node 1 pos, tan
                            },
                            zAdjustedTransf
                        ),
                        -- better make it a bridge to avoid ugly autolinks between nearby modules
                        edgeType = 'BRIDGE',
                        edgeTypeName = _autoBridgePathsRefData.bridgeTypeName_withRailing,
                        freeNodes = { 1 },
                        params = {
                            hasBus = true,
                            tramTrackType  = 'NO',
                            type = _autoBridgePathsRefData.streetTypeName_noBridge,
                        },
                        snapNodes = isSnap and { 1 } or {},
                        -- tag2nodes = {},
                        tag2nodes = {
                            [tag] = { 0, 1 } -- list of base 0 indexes of nodes
                        },
                        type = 'STREET'
                    }
                )
            end

			local terrainAlignmentList = {
				faces = {
                    transfUtils.getFaceTransformed_FAST(
                        zAdjustedTransf,
                        {
                            {-1, -2, constants.platformSideBitsZ, 1},
                            {-1, 2, constants.platformSideBitsZ, 1},
                            {1.0, 2, constants.platformSideBitsZ, 1},
                            {1.0, -2, constants.platformSideBitsZ, 1},
                        }
                    )
				},
				optional = true,
				slopeHigh = constants.slopeHigh,
				slopeLow = constants.slopeLow,
				type = 'LESS',
			}
			result.terrainAlignmentLists[#result.terrainAlignmentLists + 1] = terrainAlignmentList
		end,

        addExitPole = function(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
            return privateFuncs.flatAreas.addExitPole(result, slotTransf, tag, slotId, params, nTerminal, terminalData, nTrackEdge)
        end
    },
    lifts = {
        getPreview = function(params, isSideLift)
			local variant = (params ~= nil and type(params.variant) == 'number') and params.variant or 0
			local deltaZ, min, max = privateFuncs.getFromVariant_LiftHeight(variant)
			local arrowModelId = 'lollo_freestyle_train_station/icon/arrows_mid_blue.mdl'
			local arrowModelTransf = {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  -10, -10, 0, 1}
            local mainModelId = isSideLift and 'lollo_freestyle_train_station/lift/side_lifts_9_5_20.mdl' or 'lollo_freestyle_train_station/lift/platform_lifts_9_5_20.mdl'
			local mainModelTransf = {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 15, 1}
            if deltaZ == min then
                arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  -10, -10, 1, 1}
                mainModelId = isSideLift and 'lollo_freestyle_train_station/lift/side_lifts_9_5_10.mdl' or 'lollo_freestyle_train_station/lift/platform_lifts_9_5_10.mdl'
			elseif deltaZ == max then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  -10, -10, -1, 1}
                mainModelId = isSideLift and 'lollo_freestyle_train_station/lift/side_lifts_9_5_30.mdl' or 'lollo_freestyle_train_station/lift/platform_lifts_9_5_30.mdl'
            elseif deltaZ < 0 then
                arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  -10, -10, 1, 1}
                mainModelId = isSideLift and 'lollo_freestyle_train_station/lift/side_lifts_9_5_15.mdl' or 'lollo_freestyle_train_station/lift/platform_lifts_9_5_15.mdl'
			elseif deltaZ > 0 then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  -10, -10, -1, 1}
                mainModelId = isSideLift and 'lollo_freestyle_train_station/lift/side_lifts_9_5_25.mdl' or 'lollo_freestyle_train_station/lift/platform_lifts_9_5_25.mdl'
			end
            return {
                {
                    id = arrowModelId,
                    transf = arrowModelTransf,
                },
                {
                    id = mainModelId,
                    transf = mainModelTransf,
                },
            }
        end,
        tryGetLiftHeight = function(params, nTerminal, terminalData, nTrackEdge, slotId)
            local cpl = terminalData.centrePlatformsRelative[nTrackEdge]
            local cplP1 = terminalData.centrePlatformsRelative[nTrackEdge+1] or {}
            local bridgeHeight = (cpl.type == 1 and cplP1.type == 1)
            and (params.mainTransf[15] + cpl.posTanX2[1][1][3] - cpl.terrainHeight1)
            or 0

            local buildingHeight = 0
            if bridgeHeight < privateConstants.lifts.bridgeHeights[1] then
                buildingHeight = 0
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[2] then
                buildingHeight = 5
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[3] then
                buildingHeight = 10
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[4] then
                buildingHeight = 15
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[5] then
                buildingHeight = 20
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[6] then
                buildingHeight = 25
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[7] then
                buildingHeight = 30
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[8] then
                buildingHeight = 35
            else
                buildingHeight = 40
            end

            local variant = privateFuncs.getVariant(params, slotId)
            local deltaZ = privateFuncs.getFromVariant_LiftHeight(variant)

            buildingHeight = buildingHeight + deltaZ
            if buildingHeight < 0 then buildingHeight = 0
            elseif buildingHeight > 40 then buildingHeight = 40
            end

            return buildingHeight
        end,
        tryGetSideLiftModelId = function(params, nTerminal, nTrackEdge, eraPrefix, bridgeHeight)
            local buildingModelId = 'lollo_freestyle_train_station/lift/'
            if eraPrefix == constants.eras.era_a.prefix then buildingModelId = 'lollo_freestyle_train_station/lift/era_a_'
            elseif eraPrefix == constants.eras.era_b.prefix then buildingModelId = 'lollo_freestyle_train_station/lift/era_b_'
            end

            if bridgeHeight < privateConstants.lifts.bridgeHeights[1] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_0.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[2] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_5.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[3] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_10.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[4] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_15.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[5] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_20.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[6] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_25.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[7] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_30.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[8] then
                buildingModelId = buildingModelId .. 'side_lifts_9_5_35.mdl'
            else
                buildingModelId = buildingModelId .. 'side_lifts_9_5_40.mdl'
            end
    
            return buildingModelId
        end,
        tryGetPlatformLiftModelId = function(params, nTerminal, nTrackEdge, eraPrefix, bridgeHeight)
            local buildingModelId = 'lollo_freestyle_train_station/lift/'
            if eraPrefix == constants.eras.era_a.prefix then buildingModelId = 'lollo_freestyle_train_station/lift/era_a_'
            elseif eraPrefix == constants.eras.era_b.prefix then buildingModelId = 'lollo_freestyle_train_station/lift/era_b_'
            end
    
            if bridgeHeight < privateConstants.lifts.bridgeHeights[1] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_5.mdl' -- non linearity
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[2] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_5.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[3] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_10.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[4] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_15.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[5] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_20.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[6] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_25.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[7] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_30.mdl'
            elseif bridgeHeight < privateConstants.lifts.bridgeHeights[8] then
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_35.mdl'
            else
                buildingModelId = buildingModelId .. 'platform_lifts_9_5_40.mdl'
            end
    
            return buildingModelId
        end,
    },
    openStairs = {
--[[
        LOLLO NOTE
        I wish I could connect any stairs or lifts to whatever I like, drawing a pedestrian bridge between their "edge exits".
        Instead, I cannot connect opposite lifts or stairs if they are too close,
        eg if they are on opposite 5m platforms separated by one single track.
        checked the bridge colliders - useless
        tried disabling the new experimental flag "deferredProposal" - useless
        tried shifting the edges all the way up to 16m - useless
        Collisions always appear when the lifts are too close,
        they probably have to do with the edge mechanics.
        If the lifts / stairs are far enough, I can lay all sorts of bridges,
        even a big stock bridge, so the problem is not the bridge itself.
        For now, we live with this.
]]
        -- LOLLO OBSOLETE keep it for compatibility with older versions
        openLifts_v1_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams)
			local nTerminal, nTrackEdge, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            local _terminalData = params.terminals[nTerminal]
			local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, nTrackEdge)
			local modelId = nil
			if eraPrefix == constants.eras.era_a.prefix then modelId = 'lollo_freestyle_train_station/open_lifts/era_a_open_lift_8m.mdl'
			elseif eraPrefix == constants.eras.era_b.prefix then modelId = 'lollo_freestyle_train_station/open_lifts/era_b_open_lift_8m.mdl'
			else modelId = 'lollo_freestyle_train_station/open_lifts/era_c_open_lift_8m.mdl'
			end
			result.models[#result.models + 1] = {
				id = modelId,
				slotId = slotId,
				transf = slotTransf,
				tag = tag
			}
			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitInnerSlotId),
				shape = 1,
				spacing = {-1, 3, 0.5, 0.5},
				transf = transfUtils.getTransf_ZRotatedM90_Shifted(
					slotTransf,
					{0, -1, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitForwardSlotId),
				shape = 1,
				spacing = {-1, 3, 0.5, 0.5},
				transf = transfUtils.getTransf_Shifted(
					slotTransf,
					{1, 0, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitOuterSlotId),
				shape = 1,
				spacing = {-1, 3, 0.5, 0.5},
				transf = transfUtils.getTransf_ZRotatedP90_Shifted(
					slotTransf,
					{0, 1, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitBackwardSlotId),
				shape = 1,
				spacing = {-1, 3, 0.5, 0.5},
				transf = transfUtils.getTransf_ZRotated180_Shifted(
					slotTransf,
					{-1, 0, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
		end,
        openLifts_v2_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams)
			local nTerminal, nTrackEdge, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            local _terminalData = params.terminals[nTerminal]
			local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, nTrackEdge)
			local modelId = nil
			if eraPrefix == constants.eras.era_a.prefix then modelId = 'lollo_freestyle_train_station/open_lifts/era_a_open_lift_8m.mdl'
			elseif eraPrefix == constants.eras.era_b.prefix then modelId = 'lollo_freestyle_train_station/open_lifts/era_b_open_lift_8m.mdl'
			else modelId = 'lollo_freestyle_train_station/open_lifts/era_c_open_lift_8m.mdl'
			end

			result.models[#result.models + 1] = {
				id = modelId,
				slotId = slotId,
				transf = slotTransf,
				tag = tag
			}
			result.models[#result.models+1] = {
				id = 'lollo_freestyle_train_station/passenger_lane_open_lift_top.mdl',
				slotId = slotId,
				transf = slotTransf,
				-- tag = tag
			}

			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitInnerSlotId),
				shape = 1,
				spacing = constants.stairsEdgeSpacing,
				transf = transfUtils.getTransf_ZRotatedM90_Shifted(
					slotTransf,
					{0, -1, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitForwardSlotId),
				shape = 1,
				spacing = constants.stairsEdgeSpacing,
				transf = transfUtils.getTransf_Shifted(
					slotTransf,
					{2.5, 0, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitOuterSlotId),
				shape = 1,
				spacing = constants.stairsEdgeSpacing,
				transf = transfUtils.getTransf_ZRotatedP90_Shifted(
					slotTransf,
					{0, 1, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
			table.insert(result.slots, {
				id = result.mangleId(nTerminal, nTrackEdge, constants.idBases.openLiftExitBackwardSlotId),
				shape = 1,
				spacing = constants.stairsEdgeSpacing,
				transf = transfUtils.getTransf_ZRotated180_Shifted(
					slotTransf,
					{-2.5, 0, constants.openStairsUpZ}
				),
				type = constants.openStairsExitModuleType,
			})
		end,
        -- LOLLO OBSOLETE keep it for compatibility with older versions
        stairsExitWithEdgeModule_v1_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams, isSnap)
			local nTerminal, nTrackEdge, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            local _terminalData = params.terminals[nTerminal]
			local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, nTrackEdge)
			local modelId = privateFuncs.openStairs.getPedestrianBridgeModelId(2, eraPrefix, true)
			local transf = privateFuncs.openStairs.getExitModelTransf(slotTransf, slotId, params)

			result.models[#result.models + 1] = {
				id = modelId,
				slotId = slotId,
				transf = transf,
				tag = tag
			}
			result.models[#result.models + 1] = {
				id = 'lollo_freestyle_train_station/passenger_lane.mdl',
				slotId = slotId,
				-- transf = transfUtilsUG.mul(slotTransf, {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  -1, 0, 0, 1}),
                -- transf = transfUtils.getTransf_Shifted(slotTransf, {-1, 0, 0}),
                transf = transfUtils.getTransf_XShifted(slotTransf, -1),
				tag = tag
			}

			local _autoBridgePathsRefData = autoBridgePathsHelper.getData4Era(eraPrefix)
			table.insert(
				result.edgeLists,
				{
					alignTerrain = false, -- only align on ground and in tunnels
					edges = transfUtils.getPosTanX2Transformed(
						{
							{ { 2, 0, 0 }, { 1, 0, 0 } },  -- node 0 pos, tan
							{ { 3, 0, 0 }, { 1, 0, 0 } },  -- node 1 pos, tan
						},
						transf
					),
					edgeType = 'BRIDGE',
					edgeTypeName = _autoBridgePathsRefData.bridgeTypeName_withRailing,
					freeNodes = { 1 },
					params = {
						hasBus = true,
						tramTrackType  = 'NO',
						type = _autoBridgePathsRefData.streetTypeName_noBridge,
					},
					snapNodes = isSnap and { 1 } or {},
					tag2nodes = {},
					type = 'STREET'
				}
			)
		end,
        stairsExitWithEdgeModule_v2_updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams, isSnap, isFake)
			local nTerminal, nTrackEdge, baseId = result.demangleId(slotId)
			if not nTerminal or not baseId then return end

            local _terminalData = params.terminals[nTerminal]
			local eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, nTrackEdge)
            privateFuncs.openStairs.addExitPole(result, slotTransf, tag, slotId, params, nTerminal, _terminalData, nTrackEdge, eraPrefix)
            local transf = privateFuncs.openStairs.getExitModelTransf(slotTransf, slotId, params)
			result.models[#result.models + 1] = {
				id = 'lollo_freestyle_train_station/passenger_lane_stairs_edge.mdl',
				slotId = slotId,
				transf = transf,
				tag = tag
			}

            if (isFake) then
                result.models[#result.models + 1] = {
                    id = 'lollo_freestyle_train_station/open_stairs/' .. eraPrefix .. 'fake_edge.mdl',
                    slotId = slotId,
                    transf = transfUtils.getTransf_XShifted(transf, -0.7),
                    tag = tag
                }
            else
                local _autoBridgePathsRefData = autoBridgePathsHelper.getData4Era(eraPrefix)
                table.insert(
                    result.edgeLists,
                    {
                        alignTerrain = false, -- only align on ground and in tunnels
                        edges = transfUtils.getPosTanX2Transformed(
                            {
                                { { -0.5, 0, 0 }, { 1, 0, 0 } },  -- node 0 pos, tan
                                { { 0.5, 0, 0 }, { 1, 0, 0 } },  -- node 1 pos, tan
                            },
                            transf
                        ),
                        edgeType = 'BRIDGE',
                        edgeTypeName = _autoBridgePathsRefData.bridgeTypeName_noRailing,
                        freeNodes = { 1 },
                        params = {
                            hasBus = true,
                            tramTrackType  = 'NO',
                            type = _autoBridgePathsRefData.streetTypeName_noBridge,
                        },
                        snapNodes = isSnap and { 1 } or {},
                        -- tag2nodes = {},
                        tag2nodes = {
                            [tag] = { 0, 1 } -- list of base 0 indexes of nodes
                        },
                        type = 'STREET'
                    }
                )
            end
		end,
        getExitModelTransf = function(slotTransf, slotId, params)
            return privateFuncs.openStairs.getExitModelTransf(slotTransf, slotId, params)
        end,
        getPedestrianBridgeModelId = function(length, eraPrefix, isWithEdge)
            return privateFuncs.openStairs.getPedestrianBridgeModelId(length, eraPrefix, isWithEdge)
        end,
        getPedestrianBridgeModelId_Compressed = function(length, eraOfT1Prefix, eraOfT2Prefix)
            -- eraOfT1 and eraOfT2 are strings like 'era_a_'
            local newEraPrefix1 = eraOfT1Prefix
            if newEraPrefix1 ~= constants.eras.era_a.prefix and newEraPrefix1 ~= constants.eras.era_b.prefix and newEraPrefix1 ~= constants.eras.era_c.prefix then
                newEraPrefix1 = constants.eras.era_c.prefix
            end
            local newEraPrefix2 = eraOfT2Prefix
            if newEraPrefix2 ~= constants.eras.era_a.prefix and newEraPrefix2 ~= constants.eras.era_b.prefix and newEraPrefix2 ~= constants.eras.era_c.prefix then
                newEraPrefix2 = constants.eras.era_c.prefix
            end
            local newEraPrefix = (newEraPrefix1 > newEraPrefix2) and newEraPrefix1 or newEraPrefix2

            if length < 3 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_2m.mdl'
            elseif length < 5 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_4m.mdl'
            elseif length < 7 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_6m.mdl'
            elseif length < 10 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_8m.mdl'
            elseif length < 14 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_12m.mdl'
            elseif length < 20 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_16m.mdl'
            elseif length < 28 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_24m.mdl'
            elseif length < 40 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_32m.mdl'
            elseif length < 56 then return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_48m.mdl'
            else return 'lollo_freestyle_train_station/open_stairs/' .. newEraPrefix .. 'bridge_chunk_compressed_64m.mdl'
            end
        end,
        getPreviewIcon = function(params)
			local variant = (params ~= nil and type(params.variant) == 'number') and params.variant or 0
			local tilt, min, max = privateFuncs.getFromVariant_BridgeTilt(variant)
			local arrowModelId = 'lollo_freestyle_train_station/icon/arrows_mid_blue.mdl'
			local arrowModelTransf = {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  10, -2, 8, 1}
            if tilt == min then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  10, -2, 9, 1}
            elseif tilt == max then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_end_blue_orange.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  10, -2, 7, 1}
			elseif tilt < 0 then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, 1, 0,  0, 1, 0, 0,  -1, 0, 0, 0,  10, -2, 9, 1}
			elseif tilt > 0 then
				arrowModelId = 'lollo_freestyle_train_station/icon/arrow_blue.mdl'
				arrowModelTransf = {0, 0, -1, 0,  0, 1, 0, 0,  1, 0, 0, 0,  10, -2, 7, 1}
			end
            return {
                id = arrowModelId,
                transf = arrowModelTransf,
            }
        end,
    },
    platforms = {
        addPlatform = function(result, tag, slotId, params, nTerminal, terminalData, eraPrefix)
            -- LOLLO NOTE I can use a platform-track or dedicated models for the platform.
            -- The former is simpler, the latter requires adding an invisible track so the platform fits in bridges or tunnels.
            -- The former is a bit glitchy, the latter is prettier.
            local _isCargoTerminal = terminalData.isCargo
            if result.laneZs[nTerminal] == constants.platformHeights._0cm.aboveGround then
                local groundFacesFillKey = privateFuncs.getGroundFacesFillKey_cargo(result, nTerminal, eraPrefix)
                local terrainCoordinates = privateFuncs.platforms.getTerrainCoordinates(terminalData)
                -- I cannot raise the terrain above the invisible track, but I can paint it.
                privateFuncs.platforms.doTerrainFromCoordinates(result, nTerminal, groundFacesFillKey, terrainCoordinates)
                return
            end

            local _modules = params.modules
            local _maxIIMod10 = constants.maxPassengerWaitingAreaEdgeLength

            local _getPlatformModelId = function (eraPrefix, isCargo, isTrackOnPlatformLeft, width, ii,
            previousLeadingIndex, currentLeadingIndex, nextLeadingIndex, platformStyleModuleFileName)
                if isCargo then
                    if width < 10 then
                        if platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_earth.moduleFileName then
                            return 'lollo_freestyle_train_station/railroad/platform/earth_cargo_platform_1m_base_5m_wide.mdl'
                        elseif platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_gravel.moduleFileName then
                            return 'lollo_freestyle_train_station/railroad/platform/gravel_cargo_platform_1m_base_5m_wide.mdl'
                        else
                            return 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'cargo_platform_1m_base_5m_wide.mdl'
                        end
                    elseif width < 20 then
                        if platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_earth.moduleFileName then
                            return 'lollo_freestyle_train_station/railroad/platform/earth_cargo_platform_1m_base_10m_wide.mdl'
                        elseif platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_gravel.moduleFileName then
                            return 'lollo_freestyle_train_station/railroad/platform/gravel_cargo_platform_1m_base_10m_wide.mdl'
                        else
                            return 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'cargo_platform_1m_base_10m_wide.mdl'
                        end
                    else
                        if platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_earth.moduleFileName then
                            return 'lollo_freestyle_train_station/railroad/platform/earth_cargo_platform_1m_base_20m_wide.mdl'
                        elseif platformStyleModuleFileName == constants.cargoPlatformStyles.cargo_gravel.moduleFileName then
                            return 'lollo_freestyle_train_station/railroad/platform/gravel_cargo_platform_1m_base_20m_wide.mdl'
                        else
                            return 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'cargo_platform_1m_base_20m_wide.mdl'
                        end
                    end
                else
                    local _underpassModule = _modules[result.mangleId(nTerminal, currentLeadingIndex, constants.idBases.underpassSlotId)]
                    -- if _underpassModule ~= nil then print('ii = ') debugPrint(ii) end

                    local _isHole = _underpassModule ~= nil
                        and previousLeadingIndex == currentLeadingIndex
                        and currentLeadingIndex == nextLeadingIndex
                        -- use default coz this metadata was introduced after its modules
                        and arrayUtils.arrayHasValue(_underpassModule.metadata.holeIIs or { 3, 4, 7, 8 }, ii % _maxIIMod10)
                    if _isHole then
                        if width < 5 then
                            if platformStyleModuleFileName == constants.passengersPlatformStyles.era_b_db.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_3_1m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_3_1m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_3_1m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_3_1m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_fs_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_3_1m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_3_1m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_uk_2_stripes.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_3_1m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_3_1m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_2_stripes.moduleFileName then
                            return isTrackOnPlatformLeft
                                and 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_3_1m_wide_hole_stripe_gap_left.mdl'
                                or 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_3_1m_wide_hole_stripe_gap_right.mdl'
                            else
                            return isTrackOnPlatformLeft
                                and 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_3_1m_wide_hole_stripe_left.mdl'
                                or 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_3_1m_wide_hole_stripe_right.mdl'
                            end
                        else
                            if platformStyleModuleFileName == constants.passengersPlatformStyles.era_b_db.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_5_6m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_5_6m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_5_6m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_5_6m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_fs_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_5_6m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_5_6m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_uk_2_stripes.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_5_6m_wide_hole_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_5_6m_wide_hole_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_2_stripes.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_5_6m_wide_hole_stripe_gap_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_5_6m_wide_hole_stripe_gap_right.mdl'
                            else
                                return isTrackOnPlatformLeft
                                and 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_5_6m_wide_hole_stripe_left.mdl'
                                or 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_5_6m_wide_hole_stripe_right.mdl'
                            end
                        end
                    else
                        if width < 5 then
                            if platformStyleModuleFileName == constants.passengersPlatformStyles.era_b_db.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_3_1m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_3_1m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_3_1m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_3_1m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_fs_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_3_1m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_3_1m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_uk_2_stripes.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_3_1m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_3_1m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_2_stripes.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_3_1m_wide_stripe_gap_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_3_1m_wide_stripe_gap_right.mdl'
                            else
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_3_1m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_3_1m_wide_stripe_right.mdl'
                            end
                        else
                            if platformStyleModuleFileName == constants.passengersPlatformStyles.era_b_db.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_5_6m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_b_db_passenger_platform_1m_base_5_6m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_5_6m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_db_1s_passenger_platform_1m_base_5_6m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_fs_1_stripe.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_5_6m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_fs_1s_passenger_platform_1m_base_5_6m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_uk_2_stripes.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_5_6m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_uk_2s_passenger_platform_1m_base_5_6m_wide_stripe_right.mdl'
                            elseif platformStyleModuleFileName == constants.passengersPlatformStyles.era_c_db_2_stripes.moduleFileName then
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_5_6m_wide_stripe_gap_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/era_c_passenger_platform_1m_base_5_6m_wide_stripe_gap_right.mdl'
                            else
                                return isTrackOnPlatformLeft
                                    and 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_5_6m_wide_stripe_left.mdl'
                                    or 'lollo_freestyle_train_station/railroad/platform/' .. eraPrefix .. 'passenger_platform_1m_base_5_6m_wide_stripe_right.mdl'
                            end
                        end
                    end
                end
            end

            local _isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
            local _eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, terminalData, 1)
            local _cpfs = terminalData.centrePlatformsFineRelative
            local _platformStyleModuleFileName = result.platformStyles[nTerminal] -- it can be nil
            local _zShift = result.laneZs[nTerminal] - constants.defaultPlatformHeight
            for ii = 1, #_cpfs do
                local cpf = _cpfs[ii]
                local cpfM1 = _cpfs[ii-1] or {}
                local cpfP1 = _cpfs[ii+1] or {}
                local myTransf = transfUtils.getTransf_ZShifted(
                    privateFuncs.getPlatformObjectTransf_WithYRotation(cpf.posTanX2),
                    _zShift
                )
                local myModelId = _getPlatformModelId(
                    _eraPrefix, _isCargoTerminal, _isTrackOnPlatformLeft, cpf.width, ii,
                    cpfM1.leadingIndex, cpf.leadingIndex, cpfP1.leadingIndex, _platformStyleModuleFileName
                )
-- LOLLO NOTE platforms and sloped areas used to look wrong on humps: they were full of cuts.
-- The trouble is, edges on humps have the wrong tangents (too short)
-- Possibly, something in the handler of TRACK_BULLDOZE_REQUESTED screws up;
-- or it is a game error. However, it is hard to reproduce.
-- Whatever the cause is, this confused getNodeBetween, which now relies on an api to get the edge length.
                result.models[#result.models+1] = {
                    id = myModelId,
                    slotId = slotId,
                    tag = tag,
                    transf = myTransf
                }
            end
        end,
    },
    platformHeads = {
        updateFn = function(result, slotTransf, tag, slotId, addModelFn, params, updateScriptParams, howMany4mChunks)
            local nTerminal, nTrackEdge, baseId = result.demangleId(slotId)
			if not nTerminal or not nTrackEdge or not baseId then return end

            local headInfo = result.getOccupiedInfo4PlatformHeads(nTerminal, nTrackEdge)
            if not(headInfo.id) then return end
			-- result.models[#result.models + 1] = {
			-- 	id = 'lollo_freestyle_train_station/icon/lilac.mdl',
			-- 	slotId = slotId,
			-- 	transf = slotTransf,
			-- 	tag = tag
			-- }

			logger.print('### platformHeadModule')
			local _terminalData = params.terminals[nTerminal]
			local _cpfs = _terminalData.centrePlatformsFineRelative
			local _laneZ = result.laneZs[nTerminal]
			local _isTrackOnPlatformLeft = _terminalData.isTrackOnPlatformLeft
			local _eraPrefix = privateFuncs.getEraPrefix(params, nTerminal, _terminalData, 1)
			local _isCargoTerminal = _terminalData.isCargo
			local _platformStyleModuleFileName = result.platformStyles[nTerminal] -- it can be nil

			local _cpf = nTrackEdge == 1 and _cpfs[1] or _cpfs[#_cpfs]
			local _isRight = (_isTrackOnPlatformLeft and nTrackEdge ~= 1) or (not(_isTrackOnPlatformLeft) and nTrackEdge == 1)
			local _xSize = 4

            local _addModel = function()
                if result.laneZs[nTerminal] == constants.platformHeights._0cm.aboveGround then return end

                local _modelId = privateFuncs.platformHeads.getHeadModelId(_eraPrefix, _isCargoTerminal, _isRight, _cpf.width, _platformStyleModuleFileName)
                local posTanX2 = nTrackEdge == 1 and transfUtils.getPosTanX2Reversed(_cpf.posTanX2) or _cpf.posTanX2
                for hh = 1, howMany4mChunks do
                    -- logger.print('posTanX2 before =') logger.debugPrint(posTanX2)
                    posTanX2 = transfUtils.getExtrapolatedPosTanX2Continuation(posTanX2, _xSize)
                    -- logger.print('posTanX2 after =') logger.debugPrint(posTanX2)
                    result.models[#result.models+1] = {
                        id = _modelId,
                        slotId = slotId,
                        tag = tag,
                        transf = transfUtils.getTransf_ZShifted(
                            privateFuncs.getPlatformObjectTransf_WithYRotation(posTanX2),
                            _laneZ - constants.defaultPlatformHeight
                        )
                    }
                end
            end
            _addModel()

            local _addLanes = function()
                if _isCargoTerminal then return end

                local cpfEndPos = nTrackEdge == 1 and _cpf.posTanX2[1][1] or _cpf.posTanX2[2][1]

                local posTanX2 = nTrackEdge == 1 and transfUtils.getPosTanX2Reversed(_cpf.posTanX2) or _cpf.posTanX2
                for hh = 1, howMany4mChunks do
                    posTanX2 = transfUtils.getExtrapolatedPosTanX2Continuation(posTanX2, _xSize)
                end
                local cpfContinuationPos = transfUtils.getPositionsMiddle(posTanX2[2][1], cpfEndPos)

                local crossLength = _cpf.width * 0.5 + 2.5 -- track is always 5m wide
                if _isRight then crossLength = -crossLength end
                local sinA = (cpfContinuationPos[2] - cpfEndPos[2]) / _xSize * 2 / howMany4mChunks
                local cosA = (cpfContinuationPos[1] - cpfEndPos[1]) / _xSize * 2 / howMany4mChunks
                local headMidPos = {
                    cpfContinuationPos[1] + sinA * crossLength,
                    cpfContinuationPos[2] - cosA * crossLength,
                    cpfContinuationPos[3],
                }

                cpfEndPos = transfUtils.getPositionRaisedBy(cpfEndPos, _laneZ)
                cpfContinuationPos = transfUtils.getPositionRaisedBy(cpfContinuationPos, _laneZ)
                headMidPos = transfUtils.getPositionRaisedBy(headMidPos, _laneZ)

                if result.terminateConstructionHookInfo.autoStitchableInnerHeadPositions_by_T_I[nTerminal] == nil then
                    result.terminateConstructionHookInfo.autoStitchableInnerHeadPositions_by_T_I[nTerminal] = {}
                end
                result.terminateConstructionHookInfo.autoStitchableInnerHeadPositions_by_T_I[nTerminal][nTrackEdge] = {
                    t = nTerminal,
                    pos = cpfContinuationPos
                }
                if result.terminateConstructionHookInfo.autoStitchableOuterHeadPositions_by_T_I[nTerminal] == nil then
                    result.terminateConstructionHookInfo.autoStitchableOuterHeadPositions_by_T_I[nTerminal] = {}
                end
                result.terminateConstructionHookInfo.autoStitchableOuterHeadPositions_by_T_I[nTerminal][nTrackEdge] = {
                    t = nTerminal,
                    pos = headMidPos
                }

                local laneAlongTransf = transfUtils.get1MLaneTransf(
                    cpfEndPos,
                    cpfContinuationPos
                )
                result.models[#result.models+1] = {
                    id = constants.passengerLaneModelId,
                    slotId = slotId,
                    transf = laneAlongTransf,
                    tag = tag
                }
                local laneAcrossTransf = transfUtils.get1MLaneTransf(
                    cpfContinuationPos,
                    headMidPos
                )
                result.models[#result.models+1] = {
                    id = constants.passengerLaneModelId,
                    slotId = slotId,
                    transf = laneAcrossTransf,
                    tag = tag
                }

                -- result.models[#result.models+1] = {
                --     id = 'lollo_freestyle_train_station/icon/black.mdl',
                --     slotId = slotId,
                --     tag = tag,
                --     transf = transfUtils.transf2Position(cpfEndPos)
                -- }
                -- result.models[#result.models+1] = {
                --     id = 'lollo_freestyle_train_station/icon/white.mdl',
                --     slotId = slotId,
                --     tag = tag,
                --     transf = transfUtils.transf2Position(cpfContinuationPos)
                -- }
                -- result.models[#result.models+1] = {
                --     id = 'lollo_freestyle_train_station/icon/lilac.mdl',
                --     slotId = slotId,
                --     tag = tag,
                --     transf = transfUtils.transf2Position(headMidPos)
                -- }
            end
            _addLanes()

            local _addTerrain = function ()
                if _cpf.type ~= 0 then return end -- only on ground

                local _groundFacesFillKey = _isCargoTerminal
                    and privateFuncs.getGroundFacesFillKey_cargo(result, nTerminal, _eraPrefix)
                    or privateFuncs.getGroundFacesFillKey_passengers(_eraPrefix)
                -- local zed = privateFuncs.getIsTerrainFlush(result, nTerminal) and (-0.1) or (-constants.defaultPlatformHeight) -- need 0.1 so the module can be removed
                local zed = privateFuncs.getIsTerrainFlush(result, nTerminal) and (0.0) or (-constants.defaultPlatformHeight)
                local groundFace = { -- the ground faces ignore z, the alignment lists don't
                    {0, -_cpf.width * 0.5 - (_isRight and 0 or 5), zed, 1},
                    {0, _cpf.width * 0.5 + (_isRight and 5 or 0), zed, 1},
                    {_xSize * howMany4mChunks, _cpf.width * 0.5 + (_isRight and 5 or 0), zed + headInfo.zShift, 1},
                    {_xSize * howMany4mChunks, -_cpf.width * 0.5 - (_isRight and 0 or 5), zed + headInfo.zShift, 1},
                }
                modulesutil.TransformFaces(slotTransf, groundFace)
                table.insert(
                    result.groundFaces,
                    {
                        face = groundFace,
                        modes = {
                            {
                                type = 'FILL',
                                key = _groundFacesFillKey
                            },
                            {
                                type = 'STROKE_OUTER',
                                key = _groundFacesFillKey
                            }
                        }
                    }
                )

                local terrainAlignmentList = {
                    faces = { groundFace },
                    optional = true,
                    slopeHigh = constants.slopeHigh,
                    slopeLow = constants.slopeLow,
                    type = 'EQUAL',
                }
                result.terrainAlignmentLists[#result.terrainAlignmentLists + 1] = terrainAlignmentList
            end
            _addTerrain()
        end,
    },
    slopedAreas = {
        getYShift = function(params, nTerminal, terminalData, i, slopedAreaWidth)
            local isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
            if not(terminalData.centrePlatformsRelative[i]) then return false end

            local platformWidth = terminalData.centrePlatformsRelative[i].width
            local baseYShift = (slopedAreaWidth + platformWidth) * 0.5 -0.85
            local yShiftOutside = isTrackOnPlatformLeft and -baseYShift or baseYShift

            local yShiftOutside4StreetAccess = slopedAreaWidth * 2 -- - 1.2 -- - 1.8

            return yShiftOutside, yShiftOutside4StreetAccess
        end,
        addAll = function(result, tag, slotId, params, nTerminal, terminalData, nTrackEdge, eraPrefix, areaWidth, modelId, waitingAreaModelId, groundFacesFillKey, isCargo)
            local _isEndFiller = privateFuncs.getIsEndFillerEvery3(nTrackEdge)
            local _waitingAreaScaleFactor = areaWidth * 0.8
            local _i1 = _isEndFiller and nTrackEdge or (nTrackEdge - 1)
            local _iN = _isEndFiller and nTrackEdge or (nTrackEdge + 1)
            local _isTrackOnPlatformLeft = terminalData.isTrackOnPlatformLeft
            local _laneZ = result.laneZs[nTerminal]
            local _zShift = _laneZ - constants.defaultPlatformHeight
            local _modules = params.modules
            local _isCargoTerminal = terminalData.isCargo
            local _isTerrainFlush = privateFuncs.getIsTerrainFlush(result, nTerminal)

            local waitingAreaIndex = 0
            local nWaitingAreas = 0
            local isDecoBarred = false
            local _cpfs = terminalData.centrePlatformsFineRelative
            local _maxII = #_cpfs
            for ii = 1, _maxII do
                local cpf = _cpfs[ii]
                local leadingIndex = cpf.leadingIndex
                if leadingIndex > _iN then break end
                if leadingIndex >= _i1 then
                    -- allow any size on ground or 2.5 m on bridges
                    local isCanBuild = privateFuncs.slopedAreas.isSlopedAreaAllowed(cpf, areaWidth)
                    if isCanBuild then
                        local platformWidth = cpf.width
                        -- LOLLO TODO MAYBE check the following, it may need updating - but it is good so far.
                        -- There can be a small glitch with humps but nothing much.
                        local centreAreaPosTanX2, xRatio, yRatio = transfUtils.getParallelSideways(
                            cpf.posTanX2,
                            (_isTrackOnPlatformLeft and (-areaWidth -platformWidth) or (areaWidth + platformWidth)) * 0.5
                        )
                        local myTransf = privateFuncs.getPlatformObjectTransf_WithYRotation(centreAreaPosTanX2)
                        local xScaleFactor = math.max(xRatio * yRatio, 1.05) -- this is a bit crude but it's cheap
                        -- local xScaleFactor = xRatio * 1.05 -- dx/dl -- no good here
                        -- logger.print('xScaleFactor w ratios =', xScaleFactor)
                        result.models[#result.models+1] = {
                            id = modelId,
                            -- transf = transfUtils.getTransf_XScaled(myTransf, xScaleFactor),
                            transf = transfUtils.getTransf_Scaled_Shifted(myTransf, {xScaleFactor, 1, 1}, {0, 0, _zShift}),
                            tag = tag
                        }

                        if waitingAreaModelId ~= nil
                        and _cpfs[ii - 2] ~= nil
                        and _cpfs[ii - 2].leadingIndex >= _i1
                        and _cpfs[ii + 2] ~= nil
                        and _cpfs[ii + 2].leadingIndex <= _iN then
                            if math.fmod(waitingAreaIndex, 5) == 0 then
                                result.models[#result.models+1] = {
                                    id = waitingAreaModelId,
                                    transf = transfUtilsUG.mul(
                                        myTransf,
                                        { 0, _waitingAreaScaleFactor, 0, 0,  -_waitingAreaScaleFactor, 0, 0, 0,  0, 0, 1, 0,  0, 0, _laneZ, 1 }
                                    ),
                                    tag = slotHelpers.mangleModelTag(nTerminal, isCargo),
                                }
                                nWaitingAreas = nWaitingAreas + 1
                            end
                            waitingAreaIndex = waitingAreaIndex + 1
                        end

                        -- extend extensions along platform heads
                        local howMany1mChunks = nil
                        local platformHeadExtensionPosTanX2 = nil
                        if ii == 1 then
                            local platformHeadModule = _modules[result.mangleId(nTerminal, 1, constants.idBases.platformHeadSlotId)]
                            if platformHeadModule ~= nil then
                                -- logger.print('ii == 1; platformHeadModule =') logger.debugPrint(platformHeadModule)
                                howMany1mChunks = platformHeadModule.metadata.howMany4mChunks * 4
                                platformHeadExtensionPosTanX2 = transfUtils.getPosTanX2Reversed(centreAreaPosTanX2)
                            end
                        elseif ii == _maxII then
                            local platformHeadModule = _modules[result.mangleId(nTerminal, _cpfs[ii].leadingIndex, constants.idBases.platformHeadSlotId)]
                            if platformHeadModule ~= nil then
                                -- logger.print('ii == _maxII; platformHeadModule =') logger.debugPrint(platformHeadModule)
                                howMany1mChunks = platformHeadModule.metadata.howMany4mChunks * 4
                                platformHeadExtensionPosTanX2 = arrayUtils.cloneDeepOmittingFields(centreAreaPosTanX2)
                            end
                        end
                        if howMany1mChunks ~= nil then
                            local terrainCoordinates = {}

                            for hh = 1, howMany1mChunks do
                                -- logger.print('posTanX2 before =') logger.debugPrint(platformHeadExtensionPosTanX2)
                                platformHeadExtensionPosTanX2 = transfUtils.getExtrapolatedPosTanX2Continuation(platformHeadExtensionPosTanX2, 1)
                                -- logger.print('posTanX2 after =') logger.debugPrint(platformHeadExtensionPosTanX2)
                                local platformHeadExtensionTransf = transfUtils.getTransf_Scaled(
                                    privateFuncs.getPlatformObjectTransf_WithYRotation(platformHeadExtensionPosTanX2),
                                    {xScaleFactor, 1, 1}
                                )
                                result.models[#result.models+1] = {
                                    id = modelId, -- 'lollo_freestyle_train_station/empty.mdl'
                                    -- id = 'lollo_freestyle_train_station/icon/red.mdl',
                                    tag = tag,
                                    transf = transfUtils.getTransf_ZShifted(platformHeadExtensionTransf, _zShift)
                                }
                                -- calc terrain coordinates
                                if cpf.type == 0 then -- only on ground
                                    local x0y0Pos123 = transfUtils.getVec123Transformed({0.0, -areaWidth * 0.5, 0}, platformHeadExtensionTransf)
                                    local x0y1Pos123 = transfUtils.getVec123Transformed({0.0, areaWidth * 0.5, 0}, platformHeadExtensionTransf)
                                    local x1y1Pos123 = transfUtils.getVec123Transformed({1.0, areaWidth * 0.5, 0}, platformHeadExtensionTransf)
                                    local x1y0Pos123 = transfUtils.getVec123Transformed({1.0, -areaWidth * 0.5, 0}, platformHeadExtensionTransf)
                                    terrainCoordinates[#terrainCoordinates+1] = {
                                        x0y0Pos123,
                                        x0y1Pos123,
                                        x1y1Pos123,
                                        x1y0Pos123,
                                    }
                                    -- local onePosTanX2 = transfUtils.getParallelSidewaysCoarse(
                                    --     platformHeadExtensionPosTanX2,
                                    --     -areaWidth * 0.5
                                    -- )
                                    -- local twoPosTanX2 = transfUtils.getParallelSidewaysCoarse(
                                    --     platformHeadExtensionPosTanX2,
                                    --     areaWidth * 0.5
                                    -- )
                                    -- terrainCoordinates[#terrainCoordinates+1] = {
                                    --     twoPosTanX2[1][1],
                                    --     twoPosTanX2[2][1],
                                    --     onePosTanX2[2][1],
                                    --     onePosTanX2[1][1],
                                    -- }
                                end
                            end
                            privateFuncs.slopedAreas.doTerrainFromCoordinates(result, nTerminal, groundFacesFillKey, terrainCoordinates, _isTerrainFlush)
                        end
                    else
                        isDecoBarred = true
                        if waitingAreaModelId ~= nil
                        and _cpfs[ii - 2] ~= nil
                        and _cpfs[ii - 2].leadingIndex >= _i1
                        and _cpfs[ii + 2] ~= nil
                        and _cpfs[ii + 2].leadingIndex <= _iN then
                            if math.fmod(waitingAreaIndex, 5) == 0 then
                                nWaitingAreas = nWaitingAreas + 1
                            end
                            waitingAreaIndex = waitingAreaIndex + 1
                        end
                    end
                end
            end

            local terrainCoordinates = privateFuncs.slopedAreas.getTerrainCoordinates(result, params, nTerminal, terminalData, nTrackEdge, _isEndFiller, areaWidth, groundFacesFillKey)
            privateFuncs.slopedAreas.doTerrainFromCoordinates(result, nTerminal, groundFacesFillKey, terrainCoordinates, _isTerrainFlush)

            if waitingAreaModelId ~= nil and not(isDecoBarred) then
                local cpl = terminalData.centrePlatformsRelative[nTrackEdge]
                local verticalTransf = privateFuncs.getPlatformObjectTransf_AlwaysVertical(cpl.posTanX2)
                if isCargo then
                    privateFuncs.slopedAreas.addSlopedCargoAreaDeco(result, tag, slotId, params, nTerminal, terminalData, nTrackEdge, eraPrefix, areaWidth, nWaitingAreas, verticalTransf)
                else
                    privateFuncs.slopedAreas.addSlopedPassengerAreaDeco(result, tag, slotId, params, nTerminal, terminalData, nTrackEdge, eraPrefix, areaWidth, nWaitingAreas, verticalTransf)
                end
            end
        end,
    },
    subways = {
        doTerrain4Subways = function(result, slotTransf, groundFacesStrokeOuterKey)
            local groundFace = { -- the ground faces ignore z, the alignment lists don't
                {0.0, -0.95, 0, 1},
                {0.0, 0.95, 0, 1},
                {4.5, 0.95, 0, 1},
                {4.5, -0.95, 0, 1},
            }
            local terrainFace = { -- the ground faces ignore z, the alignment lists don't
                {-0.2, -1.15, constants.platformSideBitsZ, 1},
                {-0.2, 1.15, constants.platformSideBitsZ, 1},
                {4.7, 1.15, constants.platformSideBitsZ, 1},
                {4.7, -1.15, constants.platformSideBitsZ, 1},
            }
            if type(slotTransf) == 'table' then
                modulesutil.TransformFaces(slotTransf, groundFace)
                modulesutil.TransformFaces(slotTransf, terrainFace)
            end

            table.insert(
                result.groundFaces,
                {
                    face = groundFace,
                    loop = true,
                    modes = {
                        {
                            -- key = 'lollo_freestyle_train_station/hole.lua',
                            key = 'hole.lua',
                            type = 'FILL',
                        },
                        {
                            key = groundFacesStrokeOuterKey,
                            type = 'STROKE_OUTER',
                        }
                    }
                }
            )
            table.insert(
                result.terrainAlignmentLists,
                {
                    faces =  { terrainFace },
                    optional = true,
                    slopeHigh = constants.slopeHigh,
                    slopeLow = constants.slopeLow,
                    type = 'EQUAL',
                }
            )
        end,
        doTerrain4HollowayMedium = function(result, slotTransf, groundFacesStrokeOuterKey)
            local terrainFace = { -- the ground faces ignore z, the alignment lists don't
                {-3.4, -4.7, 0, 1},
                {-3.4, 4.7, 0, 1},
                {4.9, 4.7, 0, 1},
                {4.9, -4.7, 0, 1},
            }
            return privateFuncs.subways.doTerrain4ClosedSubways(result, slotTransf, groundFacesStrokeOuterKey, terrainFace)
        end,
        doTerrain4HollowayLarge = function(result, slotTransf, groundFacesStrokeOuterKey)
            local terrainFace = { -- the ground faces ignore z, the alignment lists don't
                {-3.4, -7.5, 0, 1},
                {-3.4, 7.5, 0, 1},
                {4.9, 7.5, 0, 1},
                {4.9, -7.5, 0, 1},
            }
            return privateFuncs.subways.doTerrain4ClosedSubways(result, slotTransf, groundFacesStrokeOuterKey, terrainFace)
        end,
        doTerrain4ClaphamLarge = function(result, slotTransf, groundFacesStrokeOuterKey)
            local terrainFace = { -- the ground faces ignore z, the alignment lists don't
                {-3.4, -3.4, 0, 1},
                {-3.4, 3.4, 0, 1},
                {2.2, 7.4, 0, 1},
                {2.2, -7.4, 0, 1},
            }
            return privateFuncs.subways.doTerrain4ClosedSubways(result, slotTransf, groundFacesStrokeOuterKey, terrainFace)
        end,
        doTerrain4ClaphamMedium = function(result, slotTransf, groundFacesStrokeOuterKey)
            local terrainFace = { -- the ground faces ignore z, the alignment lists don't
                {-2.0, -3.4, 0, 1},
                {-2.0, 3.4, 0, 1},
                {1.7, 5.8, 0, 1},
                {1.7, -5.8, 0, 1},
            }
            return privateFuncs.subways.doTerrain4ClosedSubways(result, slotTransf, groundFacesStrokeOuterKey, terrainFace)
        end,
        doTerrain4ClaphamSmall = function(result, slotTransf, groundFacesStrokeOuterKey)
            local terrainFace = { -- the ground faces ignore z, the alignment lists don't
                {-2.0, -2.9, 0, 1},
                {-2.0, 2.9, 0, 1},
                {1.7, 2.9, 0, 1},
                {1.7, -2.9, 0, 1},
            }
            return privateFuncs.subways.doTerrain4ClosedSubways(result, slotTransf, groundFacesStrokeOuterKey, terrainFace)
        end,
    },
    tubeBridge = {
        getPedestrianBridgeModelId_Compressed = function(length, eraOfT1Prefix, eraOfT2Prefix)
            -- eraOfT1 and eraOfT2 are strings like 'era_a_'
            local newEraPrefix1 = eraOfT1Prefix
            if newEraPrefix1 ~= constants.eras.era_a.prefix and newEraPrefix1 ~= constants.eras.era_b.prefix and newEraPrefix1 ~= constants.eras.era_c.prefix then
                newEraPrefix1 = constants.eras.era_c.prefix
            end
            local newEraPrefix2 = eraOfT2Prefix
            if newEraPrefix2 ~= constants.eras.era_a.prefix and newEraPrefix2 ~= constants.eras.era_b.prefix and newEraPrefix2 ~= constants.eras.era_c.prefix then
                newEraPrefix2 = constants.eras.era_c.prefix
            end
            local newEraPrefix = (newEraPrefix1 > newEraPrefix2) and newEraPrefix1 or newEraPrefix2

            if length < 6 then return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_4m.mdl'
            elseif length < 10 then return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_8m.mdl'
            elseif length < 14 then return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_12m.mdl'
            elseif length < 20 then return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_16m.mdl'
            elseif length < 28 then return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_24m.mdl'
            elseif length < 36 then return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_32m.mdl'
            elseif length < 48 then return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_40m.mdl'
            else return 'lollo_freestyle_train_station/tubeBridge/' .. newEraPrefix .. 'bridge_chunk_compressed_64m.mdl'
            end
        end,
    },
}
