--[[
    GD50
    Breakout Remake

    -- PlayState Class --

    Author: Colton Ogden
    cogden@cs50.harvard.edu

    Represents the state of the game in which we are actively playing;
    player should control the paddle, with the ball actively bouncing between
    the bricks, walls, and the paddle. If the ball goes below the paddle, then
    the player should lose one point of health and be taken either to the Game
    Over screen if at 0 health or the Serve screen otherwise.
]]

PlayState = Class{__includes = BaseState}

--[[
    We initialize what's in our PlayState via a state table that we pass between
    states as we go from playing to serving.
]]
local auxScore = 0
local powerUpTreshold = 250

function PlayState:enter(params)
    self.paddle = params.paddle
    self.bricks = params.bricks
    self.health = params.health
    self.score = params.score
    self.highScores = params.highScores
    self.ball = params.ball
    self.level = params.level

    self.recoverPoints = params.recoverPoints

    self.additionalBalls = {}
    -- give ball random starting velocity
    self.ball.dx = math.random(-200, 200)
    self.ball.dy = math.random(-50, -60)
    table.insert(self.additionalBalls, self.ball)

    self.powerup = PowerUp()
    self.lockedBall = false
    self.checkForLockedBalls = false
end

function PlayState:update(dt)
    -- Check for locked balls just once during the game
    if not self.checkForLockedBalls then
        -- check if a brick is locked to change the flag
        for k, brick in pairs(self.bricks) do
            if brick.isLocked then
                self.lockedBall = true
                break
            end
        end
        self.checkForLockedBalls = true
    end
    
    if self.paused then
        if love.keyboard.wasPressed('space') then
            self.paused = false
            gSounds['pause']:play()
        else
            return
        end
    elseif love.keyboard.wasPressed('space') then
        self.paused = true
        gSounds['pause']:play()
        return
    end

    -- update positions based on velocity
    self.paddle:update(dt)
    -- update additional balls in array
    for k, ball in pairs(self.additionalBalls) do
        ball:update(dt)
    end
    self.powerup:update(dt)
    
    -- if powerup is in play, check if it collides with paddle
    if self.powerup.inPlay and self.powerup:collides(self.paddle) then
        
        self.powerup.inPlay = false
        local createLockedBall = false
        
        -- if the powerup is a locked ball skin, create a new ball
        if self.powerup.skin == 10 then
            createLockedBall = true 
        end
        
        -- add a new ball to the table
        local newBall = Ball(math.random(6))
        
        -- Special ball to break locked bricks
        if createLockedBall then
            newBall.skin = 7
            newBall.isLocked = true
        end
        
        newBall.x = self.paddle.x + (self.paddle.width / 2) - 4
        newBall.y = self.paddle.y - 8
        newBall.dx = math.random(-200, 200)
        newBall.dy = math.random(-50, -60)
        table.insert(self.additionalBalls, newBall)
    end

    -- detects collision of paddle with the balls 
    for k, ball in pairs(self.additionalBalls) do
        if ball:collides(self.paddle) then
            -- raise ball above paddle in case it goes below it, then reverse dy
            ball.y = self.paddle.y - 8
            ball.dy = -ball.dy

            --
            -- tweak angle of bounce based on where it hits the paddle
            --

            -- if we hit the paddle on its left side while moving left...
            if ball.x < self.paddle.x + (self.paddle.width / 2) and self.paddle.dx < 0 then
                ball.dx = -50 + -(8 * (self.paddle.x + self.paddle.width / 2 - ball.x))
            
            -- else if we hit the paddle on its right side while moving right...
            elseif ball.x > self.paddle.x + (self.paddle.width / 2) and self.paddle.dx > 0 then
                ball.dx = 50 + (8 * math.abs(self.paddle.x + self.paddle.width / 2 - ball.x))
            end

            gSounds['paddle-hit']:play()
        end
    end

    -- detect collision across all bricks with the ball
    for k, brick in pairs(self.bricks) do
        for j, ball in pairs(self.additionalBalls) do
            
        -- only check collision if we're in play
            if brick.inPlay and ball:collides(brick) then
                
                -- Increase points only if brick and ball are not marked as locked
                -- or if both are locked since the locked ball can break the 
                -- locked brick
                if (not brick.isLocked and not ball.isLocked) or
                        (brick.isLocked and  ball.isLocked) or
                        (not brick.isLocked and  ball.isLocked)then

                    -- add to score
                    self.score = self.score + (brick.tier * 200 + brick.color * 25)

                    -- appears power up when score and latest recorded score are 1000 points apart
                    if self.score - auxScore >= powerUpTreshold and (not self.powerup.inPlay) then
                        auxScore = self.score + powerUpTreshold

                        self.powerup.inPlay = true
                        if self.lockedBall then
                            self.powerup.skin = math.random(2) == 1 and 10 or 8
                        else
                            self.powerup.skin = 8
                        end

                        self.powerup.x = brick.x
                        self.powerup.y = brick.y
                    end

                    -- trigger the brick's hit function, which removes it from play
                    brick:hit()

                    -- if we have enough points, recover a point of health and increase paddle size
                    if self.score > self.recoverPoints then
                        -- can't go above 3 health
                        self.health = math.min(3, self.health + 1)

                        -- multiply recover points by 2
                        self.recoverPoints = self.recoverPoints + math.min(100000, self.recoverPoints * 2)

                        -- check if paddle size is lees than 4
                        if self.paddle.size < 4 then
                            -- increase paddle size
                            self.paddle.size = math.min(4, self.paddle.size + 1)
                            self.paddle.width = 32 * self.paddle.size
                        end

                        -- play recover sound effect
                        gSounds['recover']:play()
                    end

                    -- go to our victory screen if there are no more bricks left
                    if self:checkVictory() then
                        gSounds['victory']:play()

                        gStateMachine:change('victory', {
                            level = self.level,
                            paddle = self.paddle,
                            health = self.health,
                            score = self.score,
                            highScores = self.highScores,
                            ball = self.ball,
                            recoverPoints = self.recoverPoints
                        })
                    end
                end

                --
                -- collision code for bricks
                --
                -- we check to see if the opposite side of our velocity is outside of the brick;
                -- if it is, we trigger a collision on that side. else we're within the X + width of
                -- the brick and should check to see if the top or bottom edge is outside of the brick,
                -- colliding on the top or bottom accordingly 
                --

                -- left edge; only check if we're moving right, and offset the check by a couple of pixels
                -- so that flush corner hits register as Y flips, not X flips
                if ball.x + 2 < brick.x and ball.dx > 0 then

                    -- flip x velocity and reset position outside of brick
                    ball.dx = -ball.dx
                    ball.x = brick.x - 8

                    -- right edge; only check if we're moving left, , and offset the check by a couple of pixels
                    -- so that flush corner hits register as Y flips, not X flips
                elseif ball.x + 6 > brick.x + brick.width and ball.dx < 0 then

                    -- flip x velocity and reset position outside of brick
                    ball.dx = -ball.dx
                    ball.x = brick.x + 32

                    -- top edge if no X collisions, always check
                elseif ball.y < brick.y then

                    -- flip y velocity and reset position outside of brick
                    ball.dy = -ball.dy
                    ball.y = brick.y - 8

                    -- bottom edge if no X collisions or top collision, last possibility
                else

                    -- flip y velocity and reset position outside of brick
                    ball.dy = -ball.dy
                    ball.y = brick.y + 16
                end

                -- slightly scale the y velocity to speed up the game, capping at +- 150
                if math.abs(ball.dy) < 150 then
                    ball.dy = ball.dy * 1.02
                end

                -- only allow colliding with one brick, for corners
                break
                
            end
        end
    end
    
    
    -- if a ball goes below bounds, remove it from the table
    for k, ball in pairs(self.additionalBalls) do
        if ball.y >= VIRTUAL_HEIGHT then
            table.remove(self.additionalBalls, k)
        end
    end
    
    -- check if I have no balls left
    if #self.additionalBalls == 0 then
        -- if ball goes below bounds, revert to serve state and decrease health
        if self.ball.y >= VIRTUAL_HEIGHT then
            self.health = self.health - 1
            gSounds['hurt']:play()
            
            if self.health == 0 then
                gStateMachine:change('game-over', {
                    score = self.score,
                    highScores = self.highScores
                })
            else
                gStateMachine:change('serve', {
                    paddle = self.paddle,
                    bricks = self.bricks,
                    health = self.health,
                    score = self.score,
                    highScores = self.highScores,
                    level = self.level,
                    recoverPoints = self.recoverPoints
                })
            end
        end

        if self.paddle.size > 1 then
            -- decrease paddle size
            self.paddle.size = math.max(1, self.paddle.size - 1)
            self.paddle.width = 32 * self.paddle.size
        end
        
    end

    -- for rendering particle systems
    for k, brick in pairs(self.bricks) do
        brick:update(dt)
    end

    if love.keyboard.wasPressed('escape') then
        love.event.quit()
    end
end

function PlayState:render()
    -- render bricks
    for k, brick in pairs(self.bricks) do
        brick:render()
    end

    -- render all particle systems
    for k, brick in pairs(self.bricks) do
        brick:renderParticles()
    end

    self.paddle:render()
    --self.ball:render()
    -- render additional balls in array
    for k, ball in pairs(self.additionalBalls) do
        ball:render()
    end
    self.powerup:render()

    renderScore(self.score)
    renderHealth(self.health)

    -- pause text, if paused
    if self.paused then
        love.graphics.setFont(gFonts['large'])
        love.graphics.printf("PAUSED", 0, VIRTUAL_HEIGHT / 2 - 16, VIRTUAL_WIDTH, 'center')
    end
end

function PlayState:checkVictory()
    for k, brick in pairs(self.bricks) do
        if brick.inPlay then
            return false
        end 
    end

    return true
end