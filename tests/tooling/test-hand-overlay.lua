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
assert(Overlay.facing({0,0,0},{0,0,1})==nil,'straight below')
local l,t=Overlay.text_box(100,50,40,10); near(l,80); near(t,45)
l=Overlay.text_box(100,50,40,10,'left'); near(l,100)
l=Overlay.text_box(100,50,40,10,'right'); near(l,60)
-- Install: a canvas claims a cell and draws there in pixels.
local claimed,rects,texts={},{},{}
local atlas={configure=function() end,ensure=function() return true end,
    claim=function(t,anchor) claimed[#claimed+1]=anchor; return 256,256 end,
    renderer=function() return {} end,draw=function(world,frame_for) return frame_for(claimed[1]) end}
atlas.CELL_WIDTH=960
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
print('hand_overlay=pass facing basis text_box canvas_pixels persistent_anchor')
