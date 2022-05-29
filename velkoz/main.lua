local orb = module.internal("orb")
local pred = module.internal("pred")

local kalman = module.load("fragola-aio", "kalman")()
local common = module.load("fragola-aio", "common")()

local menu = menu("fragola-aio", "Simple Velkoz Logic")
local Q = module.load("fragola-aio", "Velkoz/Q")(menu)
local W = module.load("fragola-aio", "Velkoz/W")(menu)
local E = module.load("fragola-aio", "Velkoz/E")(menu)

local minion_table = {}

local passive_buff_name = "velkozresearchstack"


local function qPredFilter(target)
    if pred.trace.newpath(target, 0.022, 0.285) and kalman:hasVelocity(Q.kalman_ms_high, target, 1350) then
        return true
    elseif pred.trace.newpath(target, 0.022, 0.410) and kalman:hasVelocity(Q.kalman_ms_high, target, 550) then
        return true
    elseif pred.trace.newpath(target, 0.015, 0.095) and kalman:hasVelocity(Q.kalman_ms_high, target, 50) then
        return true
    elseif pred.trace.newpath(target, 0.033, 0.345) and kalman:hasVelocity(Q.kalman_ms_mid, target, 1350) then
        return true
    elseif pred.trace.newpath(target, 0.033, 0.470) and kalman:hasVelocity(Q.kalman_ms_mid, target, 550) then
        return true
    elseif pred.trace.newpath(target, 0.010, 0.105) and kalman:hasVelocity(Q.kalman_ms_mid, target, 50) then
        return true
    elseif pred.trace.newpath(target, 0.033, 0.405) and kalman:hasVelocity(Q.kalman_ms_low, target, 1350) then
        return true
    elseif pred.trace.newpath(target, 0.033, 0.650) and kalman:hasVelocity(Q.kalman_ms_low, target, 550) then
        return true
    elseif pred.trace.newpath(target, 0.010, 0.125) and kalman:hasVelocity(Q.kalman_ms_low, target, 50) then
        return true
    elseif pred.trace.newpath(target, 0.025, 0.200) and kalman:hasVelocity(Q.kalman_ms_low, target, 200) then
        return true
    elseif kalman.velocity[target.networkID] < 50 and 1000 * game.time - kalman.lastboost[target.networkID] > 500 then
        return true
    elseif kalman.velocity[target.networkID] < Q.kalman_ms_high and 1000 * game.time - kalman.lastboost[target.networkID] < 55 then
        return true
    elseif kalman.velocity[target.networkID] < Q.kalman_ms_mid and 1000 * game.time - kalman.lastboost[target.networkID] < 75 then
        return true
    end
end

local function Combo()
    if not Q.menu.autoqsplit:get() then
        Q:split()
    end
    if Q.menu.useqcombo:get() then
        if Q.target and qPredFilter(Q.target) then
            Q:cast(Q.target)
        end
    end
    if W.menu.usewcombo:get() then
        W:cast(W.target)
    end
    if E.menu.useecombo:get() then
        E:cast(E.target)
    end
end

local function Mixed()
    if not Q.menu.autoqsplit:get() then
        Q:split()
    end
    if Q.menu.useqharass:get() and common:check_mana(Q.menu.qharassmana:get()) then
        if Q.target and qPredFilter(Q.target) then
            Q:cast(Q.target)
        end
    end
    if W.menu.wprocpassiveharass:get() and common:check_mana(W.menu.wharassmana:get()) and W.target then
        local buff = W.target:findBuffByName(passive_buff_name)
        if buff and buff.stacks == 2 then
            W:cast(W.target)
        end
    end
end

local function LaneClear()
    if Q.menu.useqclear:get() and common:check_mana(Q.menu.qclearmana:get()) then
        Q:clear(minion_table)
    end
    if W.menu.usewclear:get() and common:check_mana(W.menu.wclearmana:get()) and E.menu.useeclear:get() and common:check_mana(E.menu.eclearmana:get()) then
        -- W e E : prova a colpire lo stesso bersaglio
        if E:usable() and W:usable() then
            local minion_to_hit = math.max(W.menu.wminminion:get(), E.menu.eminminion:get())
            if minion_table and W:usable() and E:usable() then
                local max_nb_minion = 1
                local max_target_minion = nil
                for i=1,#minion_table do
                    local target_minion = minion_table[i]
                    if target_minion:dist()<E.pred.range then
                        local cpt = 1
                        for j=1,#minion_table do
                            if i~=j then
                                local minion = minion_table[j]
                                if minion:dist(target_minion.pos) < E.pred.radius then
                                    cpt = cpt+1
                                end
                            end
                        end
                        if cpt>max_nb_minion then
                            max_nb_minion = cpt
                            max_target_minion = target_minion
                        end
                    end
                end
                if max_nb_minion>=minion_to_hit then
                    E:cast(max_target_minion)
                    W:cast(max_target_minion)
                end
            end
        elseif E:usable() then
            E:clear(minion_table)
        elseif W:usable() then
            W:clear(minion_table)
        end
    elseif W.menu.usewclear:get() and common:check_mana(W.menu.wclearmana:get()) then
        -- W clear
        W:clear(minion_table)
    elseif E.menu.useeclear:get() and common:check_mana(E.menu.eclearmana:get()) then
        -- E clear
        E:clear(minion_table)
    end
end

local function checkMode()
    if orb.core.is_mode_active(OrbwalkingMode.Combo) then
        Combo()
    elseif orb.core.is_mode_active(OrbwalkingMode.Mixed) then
        Mixed()
    elseif orb.core.is_mode_active(OrbwalkingMode.LaneClear) then
        LaneClear()
    end
end

local function updateTarget()
    Q:updateTarget()
    W:updateTarget()
    E:updateTarget()
end

local function updateMinions()
    minion_table = {}
    for minion in objManager.minions{ team = TEAM_ENEMY, dist = Q.max_range, valid_target = true } do -- questa è una prestazione pesante, quindi lo facciamo a ritmo lento
        table.insert(minion_table,minion) -- selezioniamo i servitori in una vasta gamma e li ridurremo in seguito, quindi controlliamo tutti i servitori solo una volta
    end
end

local function slowTick()
    updateMinions()
    updateTarget()
end

local function onTick()
    kalman:UpdateSpeed()
    if Q.menu.autoqsplit:get() then
        Q:split()
    end
    checkMode()
end

local draw = function()
    Q:draw_range()
    E:draw_range()
    W:draw_range()
end

local onCreate = function(obj)
    Q:onCreate(obj)
end

local onDelete = function(obj)
    Q:onDelete(obj)
end
cb.add(cb.draw,draw)
cb.add(cb.slow_tick,slowTick)
cb.add(cb.tick,onTick)
cb.add(cb.create_object,onCreate)
cb.add(cb.delete_object,onDelete)
