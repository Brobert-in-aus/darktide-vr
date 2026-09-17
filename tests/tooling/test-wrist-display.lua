local Wrist=dofile(assert(arg[1]))
-- Bars.
local bars=Wrist.bars({health=150,max_health=200,toughness=.5,stamina=1})
assert(#bars==3 and bars[1].id=='health' and math.abs(bars[1].fraction-.75)<1e-9 and bars[1].text=='150')
assert(bars[2].id=='toughness' and bars[2].fraction==.5 and bars[3].id=='stamina')
bars=Wrist.bars({health=250,max_health=200,toughness=1.5,stamina=-1})
assert(bars[1].fraction==1 and bars[2].fraction==1 and bars[3].fraction==0,'clamped')
assert(#Wrist.bars({toughness=.3})==1,'missing values skipped')
assert(#Wrist.bars({health=10,max_health=0})==0,'zero max health')
assert(#Wrist.bars(nil)==0)
-- Colours: health white, toughness the HUD's toughness blue.
local c=Wrist.bars({health=1,max_health=2,toughness=.5,stamina=.5})
assert(c[1].color==Wrist.HEALTH_COLOR and c[1].color[1]==255 and c[1].color[2]==255 and c[1].color[3]==255)
assert(c[2].color[1]==108 and c[2].color[2]==187 and c[2].color[3]==196)
assert(Wrist.visible==nil,'always shown: no facing gate')
local tb=Wrist.bars({toughness=.5,toughness_value=74.6})
assert(tb[1].id=='toughness' and tb[1].text=='75','toughness number')
assert(Wrist.bars({toughness=.5})[1].text==nil,'no number without a value')
-- Size slider: percent, clamped to 50-200, 100 when unset.
assert(Wrist.size(nil)==1 and Wrist.size(75)==.75 and Wrist.size(10)==.5 and Wrist.size(500)==2 and Wrist.size(0/0)==1)
-- The panel scale fits the layout to the overlay cell: unchanged at the
-- 2112-wide eye target, coarser at Virtual Desktop's 90 per cent FOV tangent
-- (1908 wide), where the bars' left ends spilled into the next cell.
assert(Wrist.pixel_metres(528)==Wrist.PIXEL_METRES,'fits at 528 px')
local tight=Wrist.pixel_metres(477)
assert(tight>Wrist.PIXEL_METRES,'coarser at 477 px')
local left_end=(Wrist.BARS_LEFT+Wrist.BAR_WIDTH*.5)/tight
assert(left_end<477*.5-1,'the bars end inside the cell: '..left_end)
assert(Wrist.pixel_metres(nil)==Wrist.PIXEL_METRES and Wrist.pixel_metres(0)==Wrist.PIXEL_METRES)
print('wrist_display=pass bars clamp missing colours always_shown size pixel_metres')

