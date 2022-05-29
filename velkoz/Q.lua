local dmg = module.internal("damage")
local ts = module.internal("TS")
local pred = module.internal("pred")
local orb = module.internal("orb")

local spell_parent = module.load("fragola-aio", "spell")
local spell = class(spell_parent)

local common = module.load("fragola-aio","common")

local getTar = ts.get_result
spell.pred = {
    radius = 50, -- 50, aumentato per ridurre la collisione sui minion
    delay = 0.25,
    speed = 1300,
    range = 1100,
    collision = {
        minion = true,
        hero = true,
        walls = true,
    }
}
spell.pred2 = {
    radius = 45, -- 45, idem 
    delay = 0.5, --un po Q1+Q2? utilizzato per il controllo delle collisioni deve essere regolato ogni volta
    speed = 2100,
    range = 1100,
    collision = {
        minion = true,
        hero = true,
        walls = true,
    }
}
spell.target = nil
spell.missile = nil
spell.max_range = math.sqrt(spell.pred.range * spell.pred.range + spell.pred2.range * spell.pred2.range) --Q1+Q2 max range
spell.target_lock = nil
spell.q_split_delay = 0.066 -- deve essere regolato, il tempo necessario per dividere il proiettile, 66 ms secondo dienofail
spell.q_split_cooldown = 0.25
spell.slot = SpellSlot.Q


spell.kalman_ms_high = 750
spell.kalman_ms_mid = 500
spell.kalman_ms_low = 325

function spell:__init(menu)
    self:__super(menu)
end

function spell:makeMenu()
    self.menu:header("qcombo","Combo")
    self.menu:boolean("useqcombo","Use Q in Combo", true)
    self.menu:header("qharass","Harass")
    self.menu:boolean("useqharass", "Use Q in Harass", true)
    self.menu:slider("qharassmana","Minimum mana percentage needed", 30, 0, 100, 1)
    self.menu:header("qclear","Lane Clear")
    self.menu:boolean("useqclear","Use Q in lane clear", true)
    self.menu:slider("qminminion", "Minimum minion hit", 2, 1, 3, 1)
    self.menu:slider("qclearmana", "Minimum mana percentage needed", 30, 0, 100, 1)
    self.menu:header("qmisc","Misc")
    self.menu:boolean("autoqsplit","Auto Q Split", true)
    self.menu.autoqsplit:set(
        "tooltip",
        "Will always try to split the Q spell to hit the current target, even after manual cast"
    )
    self.menu:header("qv","")
    self.menu:menu("qvisuals","Visuals")
    self.menu.qvisuals:boolean("drawqrange","Draw Q1 range",false)
    self.menu.qvisuals:boolean("drawqmaxrange","Draw Q1+Q2 max range", true)
    self.menu.qvisuals:boolean("drawdebug", "Draw/Print Debug", false)
    self.menu:set("texture",player:spellSlot(self.slot).sprite)
end

local function normalFilter(res, tar, dist)
    -- returns the best target in range
    if dist > spell.max_range then
        return false
    end
    res.obj = tar
    return true
end

function spell:updateTarget()
    -- updates self.target with the best target
    local res = getTar(normalFilter, nil, false, true)
    if not res or not res.obj then
        return
    end
    if res.obj:isValidTarget() then 
        self.target = res.obj
    end
end

-- Start : funzioni relative al cast q deviato
function spell:calculate_splitpos(angle,target)
    local dist = target:dist()
    local vec_q1_len = dist * math.cos(angle)
    -- problem : il delay1 è sottostimato, il che porta a non raggiungere il bersaglio
    local delay = vec_q1_len / self.pred.speed + dist * math.abs(math.sin(angle)) / self.pred2.speed -- per il calcolo del delay assumiamo che la differenza con il ritardo dal future pos sia trascurabile
    local future_pos2D = pred.core.get_pos_after_time(target,delay)
    local future_pos = vec3(future_pos2D.x,future_pos2D.y)
    -- potential solution : il delay è ancora sottovalutato ma meno (c'est achille et la tortue bg)
    dist = future_pos:dist()
    vec_q1_len = dist * math.cos(angle)
    delay = vec_q1_len / self.pred.speed + dist * math.abs(math.sin(angle)) / self.pred2.speed -- per il calcolo del delay assumiamo che la differenza con il ritardo dal futuro pos sia trascurabile
    future_pos2D = pred.core.get_pos_after_time(target,delay)
    future_pos = vec3(future_pos2D.x,future_pos2D.y)
    if player:dist(future_pos) > self.max_range then 
        if self.menu.qvisuals.drawdebug:get() then print("target going out of range, angle :",angle*180/math.pi)end
        return 
    end -- supponendo che l'angolo non cambi molto

    if player:dist(future_pos)*math.abs(math.sin(angle))>self.pred2.range then 
        if self.menu.qvisuals.drawdebug:get() then print("cant reach target with q2 (angle too wide), angle : ",angle*180/math.pi)end
        return
    end

    local new_vec_q1_len = player:dist(future_pos) * math.cos(angle) -- distanza aggiornata con future pos
    if new_vec_q1_len > self.pred.range then
        if self.menu.qvisuals.drawdebug:get() then print("angle too narrow, angle : ", angle*180/math.pi)end
        return
    end
    
    local target_vec = future_pos - player.pos
    local splitpos_vec = target_vec:rotate(angle)*vec_q1_len/dist
    
    local splitpos = player.pos + splitpos_vec
    if splitpos_vec:len() / self.pred.speed < self.q_split_cooldown then
        if self.menu.qvisuals.drawdebug:get() then print("Splitpos too close to recast, angle : ",angle*180/math.pi)end
        return
    end
    local tmp_radius = self.pred.radius
    local tmp_radius2 = self.pred2.radius
    self.pred.radius = self.pred.radius + 48 -- raggio di delimitazione del minion
    self.pred2.radius = self.pred2.radius + 48
    local collision_output_q1 = pred.collision.get_prediction(self.pred,{startPos = player.pos, endPos = splitpos}) -- questo tiene conto del raggio di delimitazione dei minion? Continuo a colpire i minion se non gonfia il raggio del mio incantesimo
    if next(collision_output_q1) == nil then
        self.pred2.delay = self.q_split_delay + vec_q1_len / self.pred2.speed
        local collision_output_q2 = pred.collision.get_prediction(self.pred2,{startPos = splitpos, endPos = future_pos})
        if next(collision_output_q2) == nil then
                if self.menu.qvisuals.drawdebug:get() then print("casting at angle : ",angle*180/math.pi)end
                self.draw_seg0 = player.pos:clone()
                self.draw_seg1 = splitpos:clone()
                self.draw_seg2 = future_pos:clone()
                self.pred.radius = tmp_radius
                self.pred2.radius = tmp_radius2
                return splitpos,future_pos
        else
            if self.menu.qvisuals.drawdebug:get() then print("Collision on Q2, angle : ",angle*180/math.pi)end
        end
    else
        if self.menu.qvisuals.drawdebug:get() then print("Collision on Q1, angle :",angle*180/math.pi)end
    end
    self.pred.radius = tmp_radius
    self.pred2.radius = tmp_radius2
end

function spell:calculate_deflected_q_cast_pos(target)
    -- è necessario aggiungere un'altra logica per il cast non triangular cast!
    local number_of_angles = 20
    local angleincrement = math.pi/number_of_angles
    -- Calcola l'elenco di tutti gli splitpos validi all'istante T
    local splitpos_arr = {}
    local splitpos_out
    local future_pos
    local threshold = 150
    for i=1,math.floor(number_of_angles/2)-1 do -- pi/2 non è una possibile posizione del cast, è necessario rendere questa parte meno ambigua
        for sign=-1,1,2 do
            local alpha = i*angleincrement*sign
            splitpos_out,future_pos = self:calculate_splitpos(alpha,target)
            if splitpos_out then 
                table.insert(splitpos_arr,splitpos_out)
            end
        end
    end
    -- Calcola i migliori splitpos
    if next(splitpos_arr) == nil then -- nessuno splitpos valido
        return 
    else
        local best_index = 1
        local min_nb = 100
        for i,splitpos in pairs(splitpos_arr) do
            -- calcola il numero di minions vicini e seleziona quello con meno
            local nb_of_minions = 0
            for minion in objManager.minions{team = TEAM_ENEMY, dist = self.max_range, valid_target=true} do
                local _,_,point_on_line1 = minion.pos:proj(player.pos,splitpos)
                local _,_,point_on_line2 = minion.pos:proj(splitpos,target.pos)
                local dist1 = minion:dist(point_on_line1)
                local dist2 = minion:dist(point_on_line2)
                if dist1 < threshold or dist2 < threshold then
                    nb_of_minions = nb_of_minions + 1
                end
            end
            if nb_of_minions < min_nb then 
                min_nb = nb_of_minions
                best_index = i
            end
            
        end
        return splitpos_arr[best_index]
    end
end
-- End : funzioni relative al cast q deviato

-- Start : Farming polygons
function spell:getqsplitpolyleft_dir(splitpos,dir)
    local pm_vec = dir:perp1()
    local pmax_vec = spell.pred2.range*pm_vec/pm_vec:len()
    local orth = (pm_vec:perp1():norm()*self.pred2.radius):to2D()
    local pointmax = (pmax_vec + splitpos):to2D()
    
    local A = pointmax - orth
    local B = pointmax + orth
    local C = splitpos:to2D() + orth
    local D = splitpos:to2D() - orth
    return {A,B,C,D}
end

function spell:getqsplitpolyright_dir(splitpos,dir)
    local pm_vec = dir:perp2()
    local pmax_vec = spell.pred2.range*pm_vec/pm_vec:len()
    local orth = (pm_vec:perp2():norm()*self.pred2.radius):to2D()
    local pointmax = (pmax_vec + splitpos):to2D()
    
    local A = pointmax - orth
    local B = pointmax + orth
    local C = splitpos:to2D() + orth
    local D = splitpos:to2D() - orth
    return {A,B,C,D}
end
-- End : Farming polygons

-- Start : funzioni relative alla Q split
function spell:getqsplitpolyleft()
    local dir = self.missile.endPos2D - self.missile.startPos2D
    local pm_vec = dir:perp1():norm()
    local pmax_vec = spell.pred2.range*pm_vec
    local orth = pm_vec:perp1():norm()*self.pred2.radius/2
    local pointmax = pmax_vec + self.missile.pos2D
    
    local A = pointmax - orth
    local B = pointmax + orth
    local C = self.missile.pos2D + orth
    local D = self.missile.pos2D - orth
    return {A,B,C,D}
end

function spell:getqsplitpolyright()
    local dir = self.missile.endPos2D - self.missile.startPos2D
    local pm_vec = dir:perp2():norm()
    local pmax_vec = spell.pred2.range*pm_vec -- pmvec ridimensionato a 1000 (extended Q range)
    local orth = pm_vec:perp2():norm()*self.pred2.radius/2 -- vettore ortogonale per computer il rettangolo, larghezza = 60*2
    local pointmax = pmax_vec + self.missile.pos2D
    
    local A = pointmax - orth
    local B = pointmax + orth
    local C = self.missile.pos2D + orth
    local D = self.missile.pos2D - orth
    return {A,B,C,D}
end

function spell:split()
    -- linear pred dà risultati pessimi, facendolo ora con i buoni vecchi poligoni
    if self.target_lock and self.missile then
        local poly_left = self:getqsplitpolyleft()
        local poly_right = self:getqsplitpolyright()
        local delay = self.q_split_delay + self.target_lock:dist(self.missile.pos2D) / self.pred2.speed
        local future_pos = pred.core.get_pos_after_time(self.target_lock,delay)
        if common:insidePolygon(poly_left,future_pos) or common:insidePolygon(poly_right,future_pos) then
            player:castSpell("pos",self.slot,player.pos)
        end
    end
end
-- End : funzioni relative alla Q split

function spell:directCast(target)
    -- cast diretto al target, se possibile
    -- restituisce true se il cast ha avuto successo
    local output = pred.get_prediction(player, target, self.slot)
    if output and output.hitchance >= Hitchance.High then
        player:castSpell("pos", self.slot, output.endPos)
        return true
    end
end

function spell:deflectedCast(target)
    local splitpos = self:calculate_deflected_q_cast_pos(target)
    if splitpos then
        self.target_lock = self.far_target
        player:castSpell("pos", self.slot, splitpos)
    end
end

function spell:cast(target)
    if target and target:isValidTarget() and self:usable() and not self.missile then
        if target:dist()<self.pred.range then
            if self:directCast(target) then
                return true
            end
        else
            if target:dist()<self.max_range then
                if self:deflectedCast(target) then
                    return true
                end
            end
        end
    end
end

function spell:clear(minion_table)
    -- lancia nella posizione migliore per il clear
    if minion_table and self:usable() and not self.missile then
        local left_max_cpt=0
        local right_max_cpt=0
        local max_cpt = 0
        local max_target_minion = nil
        -- per ogni minion nel raggio, controlla se un diretto colpirà altri minion
        for i=1,#minion_table do
            local target_minion = minion_table[i]
            if target_minion:dist()<self.pred.range then
                local cpt_left = 0
                local cpt_right = 0
                local target_cpt = 0
                local vec = target_minion.pos - player.pos
                local poly_left=self:getqsplitpolyleft_dir(target_minion.pos,vec)
                local poly_right=self:getqsplitpolyright_dir(target_minion.pos,vec)
                for j=1,#minion_table do
                    if i~=j then
                        local minion = minion_table[j]
                        local flag = false
                        if cpt_left==0 and common:insidePolygon(poly_left,minion.pos2D) then
                            cpt_left = 1
                            flag = true -- impedisce allo stesso minion di contare due volte
                        end
                        if cpt_right==0 and common:insidePolygon(poly_right,minion.pos2D) and not flag then
                            cpt_right = 1
                        end
                    end
                end
                target_cpt = 1+cpt_left+cpt_right
                if target_cpt > max_cpt then
                    max_target_minion = target_minion
                    max_cpt = target_cpt
                elseif target_cpt == max_cpt then
                    local buff = target_minion:findBuffByName(self.passive_buff_name)
                    if buff and buff.stacks==2 then
                        max_target_minion = target_minion
                        max_cpt = target_cpt
                    end
                end
            end
        end
        if max_cpt>=self.menu.qminminion:get() and not self.missile then
            self:directCast(max_target_minion)
        end
    end
end

function spell:draw_range()
    if self.menu.qvisuals.drawqrange:get() then
        graphics.draw_circle(player.pos, self.pred.range, -1, 0xFF4263F5)
    end
    if self.menu.qvisuals.drawqmaxrange:get() then
        graphics.draw_circle(player.pos, self.max_range, -1, 0xFFF55902)
    end
end

function spell:onCreate(obj)
    if obj.name == "VelkozQMissile" then
        self.missile = obj
        self.target_lock = self.target
    end
end

function spell:onDelete(obj)
    if self.missile and obj == self.missile then
        self.missile = nil
    end
    if self.target_lock and obj == self.target_lock then
        self.target_lock = nil
    end
end

return spell
