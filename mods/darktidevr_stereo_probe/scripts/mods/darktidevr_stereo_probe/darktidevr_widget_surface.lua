-- One complete widget image shared by both eyes. The backend owns two distinct
-- textures: an authored capture and a display copy. No engine hooks here.
local Surface = {}
Surface.__index = Surface

local function pack(...) return {n=select('#',...), ...} end
local function finite(n)
    return type(n)=='number' and n==n and math.abs(n)<math.huge
end

function Surface.new(backend)
    assert(backend and backend.copy and backend.queue and backend.destroy)
    return setmetatable({backend=backend, revision=0}, Surface)
end

-- Identity includes HUD owner, world, target and layout generation. Callers
-- supply a stable object for one such combination, never an item's label.
-- Metadata belongs to the captured image (bounds/pivot), not a live mutable
-- scenegraph. It must be an owned snapshot created by the caller.
function Surface:capture(t, identity, metadata, draw)
    if self.destroyed or self.failed then return false, 'unavailable' end
    if not finite(t) or identity==nil or metadata==nil or type(draw)~='function' then
        return false, 'invalid_input'
    end
    if self.frame_t==t then
        -- The right eye must reuse the first eye's choice without advancing
        -- animations, recopying textures or changing the image identity.
        if self.identity~=identity then return false, 'identity_changed_within_frame' end
        return true, self.display and 'ready' or 'warming'
    end
    if self.frame_t and t<self.frame_t then self:invalidate() end
    if self.identity~=identity then
        self.pending=nil
        self.display=nil
        self.identity=identity
    end
    self.frame_t=t

    local pending=self.pending
    if pending and pending.submitted then
        local copied, detail=pcall(self.backend.copy, self.backend)
        if not copied then
            self.failed=true
            self.pending=nil
            self.display=nil
            return false, 'copy_failed', detail
        end
        self.display={identity=identity, metadata=pending.metadata,
            revision=pending.revision, captured_t=pending.t}
    else
        -- Never show the last target or keep a stale display alive when its
        -- capture world stopped rendering. Missing submission is not success.
        self.display=nil
    end

    self.revision=self.revision+1
    local revision=self.revision
    self.pending=nil
    local queued=pack(pcall(self.backend.queue, self.backend, draw, metadata, revision))
    if not queued[1] then
        -- A draw callback can have animation side effects before throwing.
        -- Propagate that error; do not invoke it a second time as a fallback.
        self.failed=true
        self.display=nil
        error(queued[2], 0)
    end
    self.pending={identity=identity, metadata=metadata, revision=revision, t=t}
    return true, self.display and 'ready' or 'warming'
end

-- Only call after the backend's owned capture world has rendered successfully.
-- A late completion for an invalidated/older capture cannot publish new content.
function Surface:submitted(revision)
    local pending=self.pending
    if not self.destroyed and not self.failed and pending and
            pending.revision==revision then pending.submitted=true end
end

function Surface:visible(t, identity)
    if self.destroyed or self.failed or self.frame_t~=t or self.identity~=identity then
        return nil
    end
    return self.display
end

-- Hidden HUD/interaction, target loss, owner changes and disabling all invalidate
-- the logical image immediately. Reusing resources must not reuse old content.
function Surface:invalidate()
    self.pending=nil
    self.display=nil
    self.frame_t=nil
    self.identity=nil
end

function Surface:destroy()
    if self.destroyed then return end
    self.destroyed=true
    self:invalidate()
    -- Retire before cleanup, so a failure cannot cause double destruction.
    self.backend:destroy()
end

return Surface
