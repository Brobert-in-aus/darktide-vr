-- Hand overlays: the panel faces the eye upright in the atlas quad's
-- convention, text boxes align, and a canvas maps metres to cell pixels.
local Overlay=dofile(assert(arg[1]))
local function near(a,b,m) assert(math.abs(a-b)<1e-9,(m or 'mismatch')..': '..tostring(a)..' vs '..tostring(b)) end
local right,forward,up=Overlay.facing({0,2,1.5},{0,0,1.5})
near(right[1],-1,'right runs to the viewer left'); near(forward[2],-1,'forward toward the viewer'); near(up[3],1,'upright')
-- A right-handed basis: right = forward x up.
local c={forward[2]*up[3]-forward[3]*up[2],forward[3]*up[1]-forward[1]*up[3],forward[1]*up[2]-forward[2]*up[1]}
near(c[1],right[1]); near(c[2],right[2]); near(c[3],right[3])
right=Overlay.facing({1,0,1},{0,0,1}); near(right[2],1,'looking +x: viewer left is +y')
assert(Overlay.facing({0,0,1},{0,0,1})==nil,'eye on the anchor')
-- Straight below with no roll to hold still draws: an arbitrary roll is what
-- the well-conditioned case would have given anyway, and a display whose
-- first frame is inside the cone -- bringing a hand back up while looking
-- down at it -- must not simply be missing (review, 18 September).
local first_right,first_forward,first_up,first_held = Overlay.facing({0,0,0},{0,0,1})
assert(first_right and first_held,'a first frame inside the cone still draws')
near(first_forward[3],1,'forward points at the eye above')
local function unit(v) return math.abs(v[1]*v[1]+v[2]*v[2]+v[3]*v[3]-1) end
assert(unit(first_right)<1e-9 and unit(first_up)<1e-9,'and the basis is still unit length')
-- Looking straight down at your own wrist is the pose the wrist display is
-- for, and it is where world up and the view direction are parallel: the roll
-- swings for a millimetre of head movement and at vertical there is none at
-- all. The last well-conditioned roll holds it steady through that cone.
local held_right,held_forward,held_up,held = Overlay.facing({0,0,0},{0,0,1},{1,0,0})
assert(held,'straight down reports a held roll')
near(held_forward[3],1,'forward still points at the eye, which is above')
near(held_right[1],1,'the held roll is kept'); near(held_right[2],0); near(held_right[3],0)
near(held_up[1],0,'up is square to both'); near(held_up[2],-1)
-- Just inside the cone it holds too, and just outside it does not.
local _,_,_,inside = Overlay.facing({0,0,0},{0.04,0,1},{1,0,0})
local _,_,_,outside = Overlay.facing({0,0,0},{0.5,0,1},{1,0,0})
assert(inside and not outside,'the cone is where the cross is ill conditioned')
-- A held frame is still orthonormal, which is what the quad needs.
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
for _,pair in ipairs({{held_right,held_forward},{held_forward,held_up},{held_up,held_right}}) do
    near(dot(pair[1],pair[2]),0,'held basis stays orthogonal')
end
near(dot(held_right,held_right),1,'held basis stays unit length')
-- And a roll that is parallel to the view cannot be re-orthogonalised.
assert(Overlay.facing({0,0,0},{0,0,1},{0,0,1})==nil,'a degenerate fallback is no fallback')
local l,t=Overlay.text_box(100,50,40,10); near(l,80); near(t,45)
l=Overlay.text_box(100,50,40,10,'left'); near(l,100)
l=Overlay.text_box(100,50,40,10,'right'); near(l,60)
-- Install: a canvas claims a cell and draws there in pixels.
local claimed,rects,texts={},{},{}
local atlas={configure=function() end,ensure=function() return true end,
    claim=function(t,anchor) claimed[#claimed+1]=anchor; return 256,256 end,
    renderer=function() return {} end,draw=function(world,frame_for) return frame_for(claimed[1]) end}
atlas.CELL_WIDTH=960; atlas.CELL_HEIGHT=1080
local Atlas={new=function(options)
    assert(options.cell_width==960 and options.cell_height==1080 and options.columns==4 and options.rows==4 and
        options.log_tag=='DARKTIDEVR_HAND_OVERLAY' and options.clock)
    return atlas end}
RESOLUTION_LOOKUP={width=3840,height=4320,scale=2}
local w,h=Overlay.extent({width=2112,height=2304,scale=1.1}); assert(w==2112 and h==2304,'the GUI layout size')
w,h=Overlay.extent({scale=2}); assert(w==3840 and h==2160,'scale fallback')
w,h=Overlay.extent(nil); assert(w==1920 and h==1080)
local api={UIRenderer={draw_rect=function(r,p,s,color) rects[#rects+1]={p,s,color} end,
    script_draw_text=function(r,text,px,font,p,s,color,options) texts[#texts+1]={text,px,p,s,color} end},
    Vector2=function(x,y) return {x,y} end,Vector3=function(x,y,z) return {x,y,z} end}
Managers={time={time=function() return 5 end}}
local box_mt={__index={store=function(self,v) self.v=v end,unbox=function(self) return self.v end}}
Vector3Box=function(v) return setmetatable({v=v},box_mt) end
package.loaded['scripts/managers/ui/ui_fonts']={get_font_options_by_style=function() return {} end}
require=function(name) return package.loaded[name] end
local overlay=Overlay.install({},{},Atlas,api)
local canvas=assert(overlay.canvas('world','ammo',{1,2,3},.001))
canvas.rect(.01,.02,.004,.002,{255,1,2,3})
near(rects[1][1][1],256+10-2,'rect x: centre 10 px right, 4 px wide'); near(rects[1][1][2],256-20-1,'rect y: up is smaller pixel y')
near(rects[1][2][1],4); near(rects[1][2][2],2)
canvas.text('7',30,0,0,{240,255,255,255})
assert(texts[1][1]=='7' and texts[1][2]==30); near(texts[1][3][1],256-960*.5); near(texts[1][4][2],45)
assert(claimed[1].key=='ammo' and claimed[1].metres==.001 and claimed[1].position:unbox()[3]==3)
overlay.canvas('world','ammo',{4,5,6},.001)
assert(claimed[2]==claimed[1] and claimed[1].position:unbox()[1]==4,'one persistent anchor per display, moved each frame')
-- Nothing a display draws reaches a neighbour's cell: rectangles are clipped
-- to the cell less a one-pixel margin (the wrist bars' left ends showed beside
-- the ammo count once the cell shrank to 477 px, 17 September).
local l,t,w,h=Overlay.clip_rect(-243,-10,343,20,477,519)
near(l,-229.5); near(t,-10); near(w,329.5); near(h,20)
l,t,w,h=Overlay.clip_rect(-100,-10,50,20,477,519)
near(l,-100); near(w,50)
assert(Overlay.clip_rect(-300,-10,40,20,477,519)==nil,'wholly outside: nothing drawn')
l,t,w,h=Overlay.clip_rect(-10,250,20,40,477,519)
near(t,250); near(h,0.5)
assert(Overlay.cell_width({width=1908,height=2076})==477 and Overlay.cell_width({width=2112,height=2304})==528)
-- Text cannot be clipped, so it is fitted: the room at a pixel offset, and
-- the font scaled down to it (a 730 px item name in a 477 px cell), dropped
-- when it would have to shrink past reading.
near(Overlay.text_room(0,477,nil),459); near(Overlay.text_room(100,477,nil),259)
near(Overlay.text_room(-100,477,'left'),329.5); near(Overlay.text_room(-100,477,'right'),129.5)
assert(Overlay.text_room(400,477,'left')==0)
assert(Overlay.fitted_font(54,300,475)==54,'fits: unchanged')
assert(Overlay.fitted_font(54,730,475)==35,'a long name shrinks to the cell')
assert(Overlay.fitted_font(54,5000,475)==nil and Overlay.fitted_font(54,10,0)==nil,'too long, or no room: not drawn')
near(Overlay.estimated_width('Ammunition Crate',54),16*54*.6)
-- Width was guarded and height was not, so a line near a cell's top or bottom
-- reached into the neighbour the way the wrist bars did sideways. Same rule:
-- the room to the nearer edge, shrink to it, drop rather than spill.
near(Overlay.vertical_room(0,1080),531,'a line on the centre has the whole half cell')
near(Overlay.vertical_room(400,1080),131); near(Overlay.vertical_room(-400,1080),131)
assert(Overlay.vertical_room(600,1080)==0 and Overlay.vertical_room(531,1080)==0,'past the edge: no room')
assert(Overlay.fitted_font(54,54*Overlay.TEXT_HALF_HEIGHT,Overlay.vertical_room(0,1080))==54,'fits: unchanged')
assert(Overlay.fitted_font(54,54*Overlay.TEXT_HALF_HEIGHT,Overlay.vertical_room(511,1080))==33,'near the edge it shrinks')
assert(Overlay.fitted_font(54,54*Overlay.TEXT_HALF_HEIGHT,Overlay.vertical_room(529,1080))==nil,'too near: not drawn')
-- And through canvas.text, which is what actually spilled: a line at the top
-- of the cell must not be drawn at its asked-for size.
texts={}
local tall=assert(overlay.canvas('world','wrist',{1,2,3},.001))
tall.text('88',54,0,0.1,{255,255,255,255})
assert(#texts==1 and texts[1][2]==54,'100 px above the centre: unchanged')
tall.text('88',54,0,0.5,{255,255,255,255})
assert(#texts==2 and texts[2][2]==51,'500 px up leaves 31 px of room, so it shrinks')
tall.text('88',54,0,0.529,{255,255,255,255})
assert(#texts==2,'529 px up is 2 px from the edge: dropped, not spilled')
-- Two fits, each allowed down to MIN_FONT_SCALE of ITS OWN input, compound to
-- the square of it: 0.35 twice is 0.12, an unreadable smear where a drop was
-- meant. The floor is measured against the size that was asked for (review,
-- 18 September). A long label near a side AND near the top is where both
-- fits bite at once.
texts={}
local corner=assert(overlay.canvas('world','holster',{1,2,3},.001))
-- 350 px right of centre takes a 518 px label to 25 px; 525 px above it
-- leaves 6 px of room, which would take that 25 to 10 -- a fifth of what was
-- asked, where the floor says a third.
corner.text('Ammunition Crate',54,0.35,0.525,{255,255,255,255})
assert(#texts==0,'both fits bit: 10 px is under the floor, so nothing is drawn')
-- One fit alone still shrinks rather than dropping.
corner.text('Ammunition Crate',54,0.35,0,{255,255,255,255})
assert(#texts==1 and texts[1][2]==25,'the width fit alone shrinks to 25 px')
assert(texts[1][2]>=54*Overlay.MIN_FONT_SCALE,'and stays above the floor')
-- The anchors were a fixed handful of hand displays; a teammate's is one per
-- player ever seen, each holding a Vector3Box, so a display that stops drawing
-- must let its anchor go. What keeps drawing keeps its anchor.
local anchors={hands={seen_t=100},['teammate_a']={seen_t=100},['teammate_b']={seen_t=91}}
assert(Overlay.stale_anchors(anchors,100)==nil,'nothing is stale on the frame it was seen')
local stale=Overlay.stale_anchors(anchors,102) or {}
assert(#stale==1 and stale[1]=='teammate_b','only the display that stopped drawing is let go')
assert(#(Overlay.stale_anchors({fresh={}},500) or {})==0,'an anchor with no time yet is kept')
assert(Overlay.ANCHOR_SWEEP_SECONDS<Overlay.ANCHOR_IDLE_SECONDS,'the sweep must run before the idle limit')
-- And the sweep as `canvas` actually runs it, on a clock that moves: the pure
-- helper above passes even if nothing ever calls it.
local now=5
Managers.time.time=function() return now end
local swept=Overlay.install({},{},Atlas,api)
local function frame(keys) for _,key in ipairs(keys) do swept.canvas('world',key,{1,2,3},.001) end end
-- The module does not expose `anchors`, so count the boxes it makes instead:
-- a swept anchor is re-created, which allocates another one.
local made=0
local counting_mt={__index={store=function(self,v) self.v=v end,unbox=function(self) return self.v end}}
Vector3Box=function(v) made=made+1 return setmetatable({v=v},counting_mt) end
frame({'ammo','wrist','teammate_a','teammate_b'}); assert(made==4,'four anchors made: '..made)
for _=1,60 do now=now+1; frame({'ammo','wrist','teammate_a','teammate_b'}) end
assert(made==4,'a display that keeps drawing keeps its anchor: '..made)
for _=1,60 do now=now+1; frame({'ammo','wrist'}) end
assert(made==4,'the two that stopped drawing are gone, not re-made')
frame({'ammo','wrist','teammate_a','teammate_b'}); assert(made==6,'the teammates return as new anchors: '..made)
-- A clock that goes backwards must not wedge the sweep for the rest of the
-- session, which is what a bare elapsed test does.
now=0
for _=1,60 do now=now+1; frame({'ammo','wrist'}) end
made=0
frame({'ammo','wrist','teammate_c'})
assert(made==1,'only the new key allocates; the sweep still runs after the clock reset')
for _=1,60 do now=now+1; frame({'ammo','wrist'}) end
made=0; frame({'ammo','wrist','teammate_c'})
assert(made==1,'and it still lets go: teammate_c had to be re-made')
swept.destroy(); made=0; frame({'ammo'})
assert(made==1,'destroy lets go of every anchor')
print('hand_overlay=pass facing basis text_box canvas_pixels persistent_anchor clip_rect cell_width stale_anchors')

