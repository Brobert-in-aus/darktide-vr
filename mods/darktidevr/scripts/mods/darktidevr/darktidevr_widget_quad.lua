-- Unloaded display geometry for a submitted complete-widget image. Use only
-- Surface:visible() images and a shared, latched head/anchor pose for both eyes.
-- No GUI allocation, depth/layer policy, engine hooks or visual acceptance here.
local Quad={}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function extent(n) return finite(n) and n>0 and n<=4096 and n==math.floor(n) end
local function mul(v,n) return {x=v.x*n,y=v.y*n,z=v.z*n} end
local function valid(v) return finite(v.x) and finite(v.y) and finite(v.z) end

function Quad.create(Plane,image,anchor,center,head_right,head_up,tangent_per_pixel)
    local m=type(image)=='table' and image.metadata
    if type(m)~='table' or type(m.bounds)~='table' or type(m.pivot)~='table' or
        not finite(m.scale) or m.scale<=0 or not extent(m.pixel_width) or not extent(m.pixel_height) or
        not extent(m.capture_width) or not extent(m.capture_height) or
        m.capture_width*m.capture_height>4194304 or
        m.pixel_width>m.capture_width or m.pixel_height>m.capture_height then
        return nil,'invalid_image'
    end
    local b,p=m.bounds,m.pivot
    if not finite(b.x) or not finite(b.y) or not finite(b.width) or not finite(b.height) or
        not finite(p.x) or not finite(p.y) or b.width<=0 or b.height<=0 then
        return nil,'invalid_image'
    end
    -- Session saves exact integer crop extents; keep them authoritative rather
    -- than rounding a second time after dividing/multiplying by capture scale.
    local left,bottom=b.x*m.scale,b.y*m.scale
    local px,py=p.x*m.scale,p.y*m.scale
    if not finite(left) or not finite(bottom) or not finite(px) or not finite(py) or
        not finite(b.width*m.scale) or not finite(b.height*m.scale) or
        math.abs(b.width*m.scale-m.pixel_width)>1e-6 or
        math.abs(b.height*m.scale-m.pixel_height)>1e-6 then return nil,'invalid_image' end
    local right,top=left+m.pixel_width,bottom+m.pixel_height
    if not finite(right) or not finite(top) or right<=left or top<=bottom then
        return nil,'invalid_image'
    end
    local plane,reason=Plane.create(anchor,center,head_right,head_up,tangent_per_pixel,{x=px,y=py})
    if not plane then return nil,reason end
    local pixel_size=plane.distance*tangent_per_pixel
    local width,height=m.pixel_width*pixel_size,m.pixel_height*pixel_size
    if not finite(pixel_size) or pixel_size<=0 or not finite(width) or not finite(height) then
        return nil,'invalid_geometry'
    end
    local position=Plane.point(plane,right,bottom)
    local x_axis,y_axis,z_axis=mul(plane.x_axis,-1/pixel_size),
        mul(plane.normal,-1),mul(plane.y_axis,1/pixel_size)
    if not valid(position) or not valid(x_axis) or not valid(y_axis) or not valid(z_axis) then
        return nil,'invalid_geometry'
    end
    -- Accepted HUD texture convention: reverse X/facing and U for readable
    -- front-face text; render-target V runs opposite logical bottom-left Y.
    -- Start at the crop's bottom-right and draw toward its bottom-left.
    return {position=position,x_axis=x_axis,y_axis=y_axis,z_axis=z_axis,
        width=width,height=height,
        uv00={x=m.pixel_width/m.capture_width,y=1},
        uv11={x=0,y=1-m.pixel_height/m.capture_height}}
end
return Quad
