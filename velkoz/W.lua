local dmg = module.internal("damage")
local ts = module.internal("TS")
local pred = module.internal("pred")
local orb = module.internal("orb")

local spell_parent = module.load("fragola-aio", "spell")
local spell = class(spell_parent)

local common = module.load("fragola-aio","common")

spell.target = nil
spell.slot = SpellSlot.W
spell.passive_buff_name = "velkozresearchstack"

local getDmg = dmg.spell
local getTar = ts.get_result

spell.pred = {
    radius = 87.5,
    speed = 1200,
    range = 1050,
    delay = 0.05 -- deve essere regolato, ufficialmente nessuno ma sembra esserci un leggero ritardo
}

function spell:__init(menu)
    self:__super(menu)
end

function spell:makeMenu()
    self.menu:header("wcombo","Combo")
    self.menu:boolean("usewcombo","Use W in Combo", true)
    self.menu:header("wharass","Harass")
    self.menu:boolean("wprocpassiveharass","Use W to proc passive", true)
    self.menu.wprocpassiveharass:set(
        "tooltip",
        "If the target already has two stacks of passive, the script will try to proc it with W. Recommended setting : on"
    )
    self.menu:slider("wharassmana","Minimum mana percentage needed", 30, 0, 100, 1)
    self.menu:header("wclear","Lane Clear")
    self.menu:boolean("usewclear","Use W in lane clear", true)
    self.menu:slider("wminminion", "Minimum minion hit", 3, 1, 7, 1)
    self.menu:slider("wclearmana", "Minimum mana percentage needed", 30, 0, 100, 1)
    self.menu:header("wmisc","Misc")
    self.menu:menu("wvisuals","Visuals")
    self.menu.wvisuals:boolean("drawwrange","Draw W range",false)
    self.menu:set("texture",player:spellSlot(self.slot).sprite)
end

local function normalFilter(res, tar, dist)
    -- restituisce il miglior bersaglio nell'intervallo
    if dist > spell.pred.range then
        return false
    end
    res.obj = tar
    return true
end

function spell:updateTarget()
    -- aggiorna self.target con il miglior target
    local res = getTar(normalFilter, nil, false, true)
    if not res or not res.obj then
        return
    end
    if res.obj:isValidTarget() then 
        self.target = res.obj
    end
end

function spell:trace_filter(input, seg, target)
    if pred.trace.linear.hardlock(input, seg, target) then
        return true
    end
    if pred.trace.linear.hardlockmove(input, seg, target) then
        return true
    end
    if seg.startPos:dist(seg.endPos) > self.pred.range then 
        return false
    end
    if pred.trace.newpath(target, 0.05, 0.5) then
        return true
    end
end

function spell:clear(minion_table)
    local minion_to_hit = self.menu.wminminion:get()
    if minion_table and self:usable() then
        local max_nb_minion = 1
        local max_target_minion = nil
        for i=1,#minion_table do
            local target_minion = minion_table[i]
            local vec = target_minion.pos - player.pos
            local maxpos = player.pos + vec*self.pred.range/vec:len()
            if target_minion:dist()<self.pred.range then
                local cpt = 1
                for j=1,#minion_table do
                    if i~=j then
                        local minion = minion_table[j]
                        local is_on_seg,point_on_seg,_ = minion.pos:proj(player.pos,maxpos)
                        if is_on_seg and minion.pos:dist(point_on_seg) < self.pred.radius then-- is the /2 really necessary?
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
            self:cast(max_target_minion)
        end
    end
end

function spell:cast(target)
    if target and target:isValidTarget() and self:usable() then
        local output = pred.get_prediction(player,target,self.slot)
        if output and output.hitchance >= Hitchance.High then
            if self:trace_filter(self.pred, output, target) or target.isMinion then
                player:castSpell("pos",self.slot,output.endPos)
            end
        end
    end
end

function spell:draw_range()
    if self.menu.wvisuals.drawwrange:get() then
        graphics.draw_circle(player.pos, self.pred.range, -1, 0xFFFF08FF)
    end
end

return spell
