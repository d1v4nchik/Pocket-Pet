// Several pets at once: how they get along. Each pair of species has its own little scenes, run by the pet that
// walked over: two cats sniff noses, groom each other or play-fight; dogs and foxes play-bow and chase each other;
// a cat and a dog are careful with each other (sometimes a hiss, then they make up); the goose honks everyone off;
// the parrot copies whoever it meets.

import Cocoa

/// What a pet is doing in a moment with a friend.
enum Social {
    case greet, approach, boop, sniff, wag, groom, groomed, crouch, pounce, swat, hopBack, bow, chase, flee, tagged, pant,
         honk, proud, startled, scurry, wary, hiss, backOff, blink, snub, confused, mimic, listen, speak
}

/// The little scene the pet that walked over runs for both of them.
enum Game { case boop, sniff, groom, fight, chase, wary, hiss, snub, honk, mimic }

extension Pet {
    /// Ready to join in: awake, on the floor, not busy, not holding still.
    var freeToPlay: Bool {
        [.idle, .walk].contains(mode) && !inAir && edge == 0 && !wallMode && stillness < 2 && !following && t > scaredUntil
            && visiting == nil && pal == nil
    }

    /// From its middle to the tip of its nose, so two pets can meet nose to nose.
    var noseReach: CGFloat { CGFloat(isBird ? (species == .goose ? 14 : 9) : 12) * s }

    /// Half its body (without nose and tail): closer than two of these, two pets look stacked on top of each other.
    var bodyHalf: CGFloat { CGFloat(isBird ? (species == .goose ? 8 : 6) : 9) * s }

    /// Another pet standing right on top of this one (napping together and playing together are meant to be close).
    func crowding() -> Pet? {
        guard edge == 0, !inAir, !wallMode else { return nil }
        return world.pets.first { o in
            o !== self && o !== pal && o.edge == 0 && !o.inAir && !o.wallMode && o.mode != .held && abs(o.y - y) < 30
                && abs(o.x - x) < bodyHalf + o.bodyHalf + 2 * s && !(isAsleep && o.isAsleep)
        }
    }

    /// Which of two crowded pets moves: the one that isn't busy, else the one added later.
    func shouldYield(to o: Pet) -> Bool {
        let busy: Set<Mode> = [.typing, .watching, .listening, .sleeping, .catnap, .yawning, .eating, .agenda, .social, .ball, .waking]
        if busy.contains(o.mode) { return true }
        let i = world.pets.firstIndex { $0 === self } ?? 0, j = world.pets.firstIndex { $0 === o } ?? 0
        return i > j
    }

    /// A free spot near `target`: beside any pet resting there instead of on top of it.
    func roomy(_ target: CGFloat) -> CGFloat {
        var gx = target
        for o in world.pets where o !== self && o.edge == 0 && !o.inAir && !o.wallMode && abs(o.y - y) < 30 && o.mode != .walk {
            let need = bodyHalf + o.bodyHalf + 6 * s
            guard abs(o.x - gx) < need else { continue }
            let side: CGFloat = abs(gx - o.x) < 1 ? (x < o.x ? -1 : 1) : (gx < o.x ? -1 : 1)
            gx = o.x + side * need
            if floorClamp(gx) != gx { gx = o.x - side * need }
        }
        return floorClamp(gx)
    }

    /// Standing on top of another pet for a while: stroll a step to the side.
    func makeRoom() -> Bool {
        guard !inPlace, let o = crowding(), o.mode != .walk, shouldYield(to: o) else { return false }
        let side: CGFloat = abs(x - o.x) < 1 ? (Bool.random() ? 1 : -1) : (x < o.x ? -1 : 1)
        walkTarget = roomy(o.x + side * (bodyHalf + o.bodyHalf + 6 * s))
        guard abs(walkTarget - x) > 3 else { return false }
        running = false
        setMode(.walk)
        return true
    }

    func floorClamp(_ v: CGFloat) -> CGFloat {
        let vf = world.area(near: CGPoint(x: x, y: y))
        return clamp(v, vf.minX + margin, vf.maxX - margin)
    }

    /// Got to the friend it walked over to: pick what to do together, the way these two species would.
    func meet(_ f: Pet) {
        guard f.freeToPlay, abs(f.y - y) < 40 else { quickHi(f); return }
        let a = family, b = f.family
        let playful = happiness > 45 && energy > 35 && f.energy > 35 && !f.inPlace
        let g: Game
        if species == .goose || f.species == .goose {
            g = species == .goose && f.species == .goose ? .honk : (chance(0.7) ? .honk : .boop)
        } else if species == .parrot || f.species == .parrot {
            g = chance(0.8) ? .mimic : .boop
        } else if a == .cat && b == .cat {
            g = playful && chance(0.4) ? .fight : chance(0.45) ? .groom : .boop
        } else if a == .dog && b == .dog {
            g = playful && chance(0.5) ? .chase : playful && chance(0.35) ? .fight : chance(0.5) ? .sniff : .boop
        } else if (a == .cat && b == .dog) || (a == .dog && b == .cat) {
            g = a == .dog && playful && chance(0.3) ? .snub : chance(0.4) ? .hiss : .wary
        } else {
            g = .boop
        }
        start(g, with: f)
    }

    /// The friend's busy: just a word and a heart from a little way off.
    func quickHi(_ f: Pet) {
        if abs(f.x - x) > 2 { facing = f.x > x ? 1 : -1 }
        say([["HI!", species.vocal.word + "!"].randomElement()!], 1.4)
        hearts(1)
        setMode(.idle); act = isBird ? .stand : .sit; actT = 0; actDur = rnd(2, 3.5)
    }

    func start(_ g: Game, with f: Pet) {
        game = g; stage = 0; stageT = 0; gameT = 0; legs = 0
        rounds = g == .chase ? Int.random(in: 2...4) : g == .fight ? Int.random(in: 1...2) : 1
        let catFriend = f.family == .cat && (g == .wary || g == .hiss)
        join(.approach, f)
        f.join(catFriend ? .wary : .greet, self)
        let reach = noseReach + f.noseReach
        let extra: CGFloat
        switch g {
        case .boop, .sniff: extra = -1
        case .groom: extra = -5
        case .fight: extra = 16
        case .chase, .snub: extra = 12
        case .wary, .hiss: extra = 2
        case .honk: extra = 8
        case .mimic: extra = 6
        }
        let careful = g == .wary || g == .hiss
        // grooming cats sit close enough for their heads to touch; everyone else meets nose to nose (or a hop away)
        head(to: f, gap: g == .groom ? 11 * s : reach + extra * s, careful ? (family == .cat ? 18 : 26) : 36)
        world.lastPlay = t
        nextSocial = t + rnd(40, 90)
        f.nextSocial = t + rnd(30, 60)
    }

    /// Joins (or switches to) a moment with a friend.
    func join(_ k: Social, _ friend: Pet) {
        social = k; pal = friend; socialT = 0; socialGoal = nil; wiggling = false
        if mode != .social { setMode(.social) }
    }

    /// Walks up to `gap` from the friend, staying on its own side unless there's no room there.
    func head(to f: Pet, gap: CGFloat, _ speed: CGFloat, run: Bool = false) {
        var side: CGFloat = x <= f.x ? -1 : 1
        if floorClamp(f.x + side * gap) != f.x + side * gap { side = -side }
        let gx = floorClamp(f.x + side * gap)
        socialSpeed = speed; socialRun = run
        socialGoal = abs(gx - x) < 3 ? nil : gx
    }

    /// Runs off: away from the friend, or back the other way when there's no room left.
    func runOff(from f: Pet, _ speed: CGFloat) {
        var dir: CGFloat = x >= f.x ? 1 : -1
        var gx = floorClamp(x + dir * rnd(240, 400))
        if abs(gx - x) < 90 { dir = -dir; gx = floorClamp(x + dir * rnd(240, 400)) }
        socialGoal = gx; socialSpeed = speed; socialRun = true
    }

    func faceEach(_ f: Pet) {
        guard abs(f.x - x) > 1 else { return }
        facing = f.x > x ? 1 : -1
        f.facing = -facing
    }

    /// Ends the moment for both of them, each with something calm to do next.
    func endSocial(_ mine: IdleAct? = nil, _ theirs: IdleAct? = nil) {
        let f = pal
        finishSocial(mine)
        if let f, f.pal === self { f.finishSocial(theirs) }
    }

    func finishSocial(_ a: IdleAct?) {
        pal = nil; game = nil; socialGoal = nil; wiggling = false; running = false; leapV = 0
        guard mode == .social else { return }
        setMode(.idle)
        var next = a ?? (isBird ? .stand : .sit)
        if next == .groom && family != .cat { next = .sit }
        if next == .preen && !isBird { next = .sit }
        if isBird && [.sit, .groom, .lie].contains(next) { next = .stand }
        act = next; actT = 0; actDur = rnd(2.5, 4.5)
    }

    // MARK: Every frame

    func socialStep(_ dt: Double) {
        socialT += dt
        guard let f = pal, f.pal === self, f.mode == .social, !f.inAir, f.edge == 0, !inAir, edge == 0,
              !world.items.contains(where: { !$0.gone && ($0.isFood || $0.isBall) }) else { endSocial(); return }
        switch social {
        case .chase:
            go(f.x, speed: socialSpeed, dt, run: true)
        case .backOff:
            if !inPlace {
                let away: CGFloat = x < f.x ? -1 : 1
                x = floorClamp(x + away * 30 * s / 4 * CGFloat(dt))
                moving = true; walkT += dt * 0.5
            }
            if abs(f.x - x) > 1 { facing = f.x > x ? 1 : -1 }
        default:
            if let g = socialGoal {
                // still far off: an ordinary walk; the last bit at the scene's own pace (slow and careful, or brisk)
                let far = social == .approach && abs(g - x) > 40 * s
                let speed = far ? max(socialSpeed, isBird ? 55 : family == .dog ? 50 : 42) : socialSpeed
                if go(g, speed: speed, dt, run: socialRun) { socialGoal = nil; moving = false }
            } else if social == .snub {
                if abs(f.x - x) > 1 { facing = f.x > x ? -1 : 1 }          // turns its back
            } else if social != .wag && social != .pounce && social != .hopBack && abs(f.x - x) > 2 {
                facing = f.x > x ? 1 : -1
            }
        }
        if let g = game { runGame(g, f, dt) } else if socialT > 40 { endSocial() }
    }

    /// Fires once, the frame the scene's clock passes `s` seconds.
    func cross(_ s: Double) -> Bool { stageT >= s && stageT - lastDT < s }

    func runGame(_ g: Game, _ f: Pet, _ dt: Double) {
        stageT += dt; gameT += dt; lastDT = dt
        if gameT > 40 { endSocial(); return }
        if stage == 0 {                                   // walking up to the friend
            if socialGoal == nil { moving = false; faceEach(f); enter(g, f, 1) }
            else if stageT > 15 { endSocial() }           // couldn't get there: never mind
            return
        }
        switch g {
        case .boop: boopScene(f)
        case .sniff: sniffScene(f)
        case .groom: groomScene(f)
        case .fight: fightScene(f)
        case .chase: chaseScene(f)
        case .wary, .hiss: waryScene(f, hiss: g == .hiss)
        case .snub: snubScene(f)
        case .honk: honkScene(f)
        case .mimic: mimicScene(f)
        }
    }

    func enter(_ g: Game, _ f: Pet, _ st: Int) {
        stage = st; stageT = 0
        switch (g, st) {
        case (.boop, 1), (.sniff, 1), (.wary, 2), (.hiss, 13):
            booping(f)
        case (.groom, 1): join(.groom, f); f.join(.groomed, self); world.synth.play(f.purr)
        case (.groom, 2): f.join(.groom, self); join(.groomed, f); world.synth.play(purr)
        case (.fight, _): break                            // the fight scene handles its own steps
        case (.chase, 1):
            join(.bow, f); f.join(.greet, self)
            world.synth.play(species.vocal.sound); if chance(0.6) { say(["RUFF!"], 1) }
        case (.wary, 1), (.hiss, 1):
            let cat = family == .cat ? self : f, dog = cat === self ? f : self
            cat.join(.wary, dog); dog.join(.greet, cat)
        case (.snub, 1):
            join(.bow, f); f.join(.greet, self)
            world.synth.play(species.vocal.sound); say(["RUFF!"], 1)
        case (.snub, 2): f.join(.snub, self)
        default: break
        }
    }

    // MARK: Scenes

    /// Nose to nose: a sniff and a boop.
    func booping(_ f: Pet) {
        join(.boop, f); f.join(.boop, self)
        if family == .cat || f.family == .cat { world.synth.play((family == .cat ? self : f).mrrp) }
    }

    func boopScene(_ f: Pet) {
        if cross(0.6) { hearts(1); f.hearts(1) }
        if stageT > 1.4 {
            happiness = min(100, happiness + 4); f.happiness = min(100, f.happiness + 4)
            endSocial(family == .cat ? .groom : .sit, f.family == .cat ? .groom : .sit)
        }
    }

    /// Dogs: noses first, then a polite sniff round the back while the other one wags.
    func sniffScene(_ f: Pet) {
        switch stage {
        case 1:
            if cross(0.6) { hearts(1) }
            if stageT > 1.2 {
                stage = 2; stageT = 0
                f.join(.wag, self)
                join(.approach, f)
                let behind = f.x - CGFloat(f.facing) * 25 * s
                socialGoal = floorClamp(behind); socialSpeed = 30; socialRun = false
            }
        case 2:
            if socialGoal == nil || stageT > 5 { socialGoal = nil; join(.sniff, f); stage = 3; stageT = 0 }
        default:
            if stageT > 1.8 {
                happiness = min(100, happiness + 4); f.happiness = min(100, f.happiness + 5)
                endSocial(.sit, .stand)
            }
        }
    }

    /// Cats: one grooms the other, who leans into it purring; sometimes it returns the favour.
    func groomScene(_ f: Pet) {
        let groomed = stage == 1 ? f : self
        if cross(1.0) || cross(2.3) { groomed.hearts(1) }
        if stage == 1 && stageT > 3.4 {
            if chance(0.45) { enter(.groom, f, 2) } else { finishGroom(f) }
        } else if stage == 2 && stageT > 2.6 {
            finishGroom(f)
        }
    }

    func finishGroom(_ f: Pet) {
        happiness = min(100, happiness + 5); f.happiness = min(100, f.happiness + 6)
        endSocial(.groom, .lie)
    }

    /// Play-fight: the attacker crouches with a wiggle, pounces, they rear up and swat, and the other hops back.
    /// With two rounds, they swap. Ears go back but nobody gets hurt.
    func fightScene(_ f: Pet) {
        let (a, b) = legs % 2 == 0 ? (self, f) : (f, self)
        switch stage {
        case 1:                                                       // wind-up
            if stageT < lastDT + 0.001 {
                a.join(.crouch, b); a.wiggling = true; b.join(.crouch, a)
                stageLen = rnd(1.0, 1.6)
            }
            if stageT > stageLen {
                stage = 2; stageT = 0
                a.faceEach(b)
                a.join(.pounce, b); b.join(.swat, a)
                let travel = max(0, abs(b.x - a.x) - (a.noseReach + b.noseReach - 6 * s))
                if !a.inPlace { a.hopV = 330 * s / 4; a.leapV = CGFloat(a.facing) * travel / 0.44 } else { a.hopV = 200 * s / 4 }
                world.synth.play(a.family == .cat ? a.mrrp : "woof")
                if chance(0.5) { a.say([a.species == .redPanda ? "HUFF!" : a.family == .cat ? "MRRP!" : "RUFF!"], 1) }
            }
        case 2:                                                       // in the air
            if a.hopY == 0 && stageT > 0.2 {
                stage = 3; stageT = 0; stageLen = rnd(1.6, 2.2)
                a.leapV = 0; a.faceEach(b)
                a.join(.swat, b); b.join(.swat, a); b.swatOffset = 0.07; a.swatOffset = 0
            }
        case 3:                                                       // the scuffle
            if cross(0.5) || cross(1.3) { (chance(0.5) ? a : b).stars(1) }
            if cross(0.8) { a.hopV = 110 * s / 4 }
            if cross(1.1) { b.hopV = 110 * s / 4 }
            if stageT > stageLen {
                stage = 4; stageT = 0
                b.join(.hopBack, a); a.join(.crouch, b)
                b.hopV = 230 * s / 4
                let back = b.floorClamp(b.x - CGFloat(b.facing) * 55 * s / 4)
                if !b.inPlace && abs(back - (b.x - CGFloat(b.facing) * 55 * s / 4)) < 1 { b.leapV = -CGFloat(b.facing) * 125 * s / 4 }
            }
        case 4:                                                       // apart again
            if stageT > 0.8 {
                legs += 1
                if legs < rounds { stage = 1; stageT = 0 } else {
                    stage = 5; stageT = 0
                    join(.pant, f); f.join(.pant, self)
                }
            }
        default:                                                      // out of breath, then calm
            if stageT > (family == .cat ? 1.4 : 2.4) {
                energy = max(0, energy - 5); f.energy = max(0, f.energy - 5)
                happiness = min(100, happiness + 6); f.happiness = min(100, f.happiness + 6)
                endSocial(.groom, .groom)
            }
        }
    }

    /// Dogs and foxes: play bow, then one runs and the other chases; caught, they swap.
    func chaseScene(_ f: Pet) {
        switch stage {
        case 1:                                                       // both bow
            if cross(0.45) { f.join(.bow, self); f.world.synth.play(f.species.vocal.sound) }
            if stageT > 1.3 { startLeg(f) }
        case 2:                                                       // running
            let (runner, chaser) = legs % 2 == 0 ? (self, f) : (f, self)
            if runner.socialGoal == nil { runner.runOff(from: chaser, runner.socialSpeed) }
            if stageT > 3.5 { runner.socialSpeed = 120 }              // lets itself get caught
            if (abs(runner.x - chaser.x) < 20 * s && stageT > 0.6) || stageT > 7 {     // nose reaches tail: tagged
                stage = 3; stageT = 0
                runner.spawnBang()
                chaser.world.synth.play(chaser.species.vocal.sound)
                runner.join(.tagged, chaser); chaser.join(.tagged, runner)
                faceEach(f)
            }
        case 3:                                                       // tagged: a beat, then swap
            if stageT > 0.5 {
                legs += 1
                if legs < rounds { startLeg(f) } else {
                    stage = 4; stageT = 0
                    join(.pant, f); f.join(.pant, self)
                }
            }
        default:
            if cross(0.3) || cross(1.3) { spawnDrop(); f.spawnDrop() }
            if stageT > 2.4 {
                energy = max(0, energy - 6); f.energy = max(0, f.energy - 6)
                happiness = min(100, happiness + 7); f.happiness = min(100, f.happiness + 7)
                endSocial(.sit, .sit)
            }
        }
    }

    func startLeg(_ f: Pet) {
        stage = 2; stageT = 0
        let (runner, chaser) = legs % 2 == 0 ? (self, f) : (f, self)
        runner.join(.flee, chaser); chaser.join(.chase, runner)
        runner.runOff(from: chaser, 185)
        chaser.socialSpeed = 225
    }

    /// A cat and a dog: a careful sniff. Fine, a boop. Not fine: a hiss, the dog backs off, the cat calms down
    /// with a slow blink and the dog comes back in for a boop.
    func waryScene(_ f: Pet, hiss: Bool) {
        let cat = family == .cat ? self : f, dog = cat === self ? f : self
        switch stage {
        case 1:
            if stageT > 1.6 {
                if hiss {
                    stage = 10; stageT = 0
                    cat.join(.hiss, dog); dog.join(.startled, cat)
                    world.synth.play("hiss"); cat.say([cat.species == .redPanda ? "HUFF!" : "HSSS!"], 1.2)     // a red panda's huff
                    if !dog.inPlace { dog.hopV = 170 * s / 4 }
                    dog.spawnBang()
                } else { enter(.wary, f, 2) }
            }
        case 2: boopScene(f)
        case 10:
            if cross(0.45) { dog.join(.backOff, cat) }
            if stageT > 1.9 { stage = 11; stageT = 0; cat.join(.blink, dog); dog.join(.confused, cat) }
        case 11:
            if stageT > 1.8 {
                stage = 12; stageT = 0
                cat.join(.greet, dog); dog.join(.approach, cat)
                dog.head(to: cat, gap: dog.noseReach + cat.noseReach - s, 24)
            }
        case 12:
            if dog.socialGoal == nil || stageT > 5 { dog.socialGoal = nil; dog.faceEach(cat); enter(.hiss, f, 13) }
        default:
            boopScene(f)                                              // made up
        }
    }

    /// A dog play-bows at a cat. The cat is not impressed: it turns its back and washes.
    func snubScene(_ f: Pet) {
        switch stage {
        case 1:
            if stageT > 1.5 { enter(.snub, f, 2) }
        default:
            if cross(0.6) { join(.confused, f) }
            if cross(0.8) { spawn(.question, Double(head.x), Double(head.y) - 3, vy: -2, life: 1.2) }
            if stageT > 2.8 { endSocial(.sit, .groom) }
        }
    }

    /// The goose honks with its head down and wings out; the other one jumps and scurries off, the goose chases a few
    /// steps and stands tall. Two geese just honk at each other.
    func honkScene(_ f: Pet) {
        if species == .goose && f.species == .goose { honkDuet(f); return }
        let goose = species == .goose ? self : f, other = goose === self ? f : self
        switch stage {
        case 1:
            if stageT < lastDT + 0.001 {
                goose.join(.honk, other); other.join(.greet, goose)
                world.synth.play("honk"); goose.say(["HONK!"], 1.2)
            }
            if cross(0.22) {
                other.join(.startled, goose); other.spawnBang()
                if !other.inPlace && other.family != .turtle { other.hopV = 250 * s / 4 }      // a turtle just pulls in
                world.synth.play(other.species.vocal.sound)
                other.say([other.family == .cat ? other.eek : other.family == .dog ? "YIP!" : "SQUAWK!"], 1)
            }
            if cross(0.55) { world.synth.play("honk") }
            if stageT > 0.8 {
                stage = 2; stageT = 0
                other.join(.scurry, goose)
                other.runOff(from: goose, 210)
                other.socialGoal = other.floorClamp(other.x + (other.x >= goose.x ? 1 : -1) * rnd(170, 260))
                if abs(other.socialGoal! - other.x) < 60 || other.family == .turtle { other.socialGoal = nil }   // cornered (or a turtle): it stays put
                let dir: CGFloat = other.x >= goose.x ? 1 : -1
                goose.socialGoal = goose.floorClamp(goose.x + dir * 70 * s / 4); goose.socialSpeed = 90; goose.socialRun = false
            }
        case 2:
            if cross(0.6) { world.synth.play("honk") }
            if (other.socialGoal == nil && stageT > 0.8) || stageT > 2.6 {
                stage = 3; stageT = 0
                other.socialGoal = nil
                goose.join(.proud, other)
            }
        default:
            if cross(0.3) { other.spawnDrop() }
            if stageT > 1.8 { endSocial(goose === self ? .preen : .look, goose === self ? .look : .preen) }
        }
    }

    func honkDuet(_ f: Pet) {
        switch stage {
        case 1:
            if stageT < lastDT + 0.001 { join(.honk, f); f.join(.listen, self); world.synth.play("honk"); say(["HONK!"], 1) }
            if stageT > 1.0 { stage = 2; stageT = 0; f.join(.honk, self); join(.listen, f); world.synth.play("honk"); f.say(["HONK HONK!"], 1.1) }
        case 2:
            if stageT > 1.1 { stage = 3; stageT = 0; join(.honk, f); f.join(.honk, self); world.synth.play("honk") }
        default:
            if cross(0.4) { world.synth.play("honk") }
            if stageT > 1.0 { endSocial(.preen, .preen) }
        }
    }

    /// The parrot says the other pet's word in its voice; the other one stares, answers, and gets copied again.
    func mimicScene(_ f: Pet) {
        let parrot = species == .parrot ? self : f, other = parrot === self ? f : self
        let both = species == .parrot && f.species == .parrot
        let word = both ? "HELLO" : other.species.vocal.word
        let sound = other.species == .parrot ? "squawk" : other.species.vocal.sound
        switch stage {
        case 1:
            if stageT < lastDT + 0.001 {
                parrot.join(.mimic, other); other.join(.listen, parrot)
                parrot.say(["\(word)!"], 1.2); world.synth.play(sound)
            }
            if cross(0.6) && !both { other.spawn(.question, Double(other.head.x), Double(other.head.y) - 3, vy: -2, life: 1) }
            if stageT > 1.3 {
                stage = 2; stageT = 0
                if both { other.join(.mimic, parrot) } else { other.join(.speak, parrot) }
                parrot.join(.listen, other)
                other.say([both ? "HELLO!" : "\(word)?"], 1.1); world.synth.play(sound)
            }
        case 2:
            if stageT > 1.1 {
                stage = 3; stageT = 0
                parrot.join(.mimic, other)
                if both { other.join(.mimic, parrot) }
                else { other.join(.listen, parrot) }
                parrot.say([both ? "PRETTY BIRD!" : "\(word)? \(word)?"], 1.4); world.synth.play(sound)
            }
        default:
            if cross(0.45) { world.synth.play(sound) }
            if cross(0.7) { other.hearts(1); parrot.hearts(1) }
            if stageT > 1.5 {
                happiness = min(100, happiness + 4); f.happiness = min(100, f.happiness + 4)
                endSocial()
            }
        }
    }

    // MARK: Poses

    func socialPose(_ p: inout Pose) {
        let k = socialT
        let flap = Int(t / 0.09) % 2 == 0
        let dog = family == .dog, bird = isBird
        if moving {                                       // walking or running: the walk cycle, with the right face
            switch social {
            case .flee, .scurry: p.eyes = .wide; p.tailUp = social == .flee; p.earsFlat = social == .scurry
                if bird { p.arm = flap ? .raised : .rest }
            case .chase: p.eyes = .happy; p.tailUp = true
            case .backOff: p.earsFlat = true; p.eyes = .sad; p.tailUp = false; if dog { p.mouth = .closed }
            case .honk: p.arm = flap ? .raised : .rest; p.mouth = Int(t / 0.1) % 2 == 0 ? .open : .closed; p.eyes = .angry
                if species == .goose { p.headDX = 4; p.headDY = 5 }
            default: break
            }
            if dog && social != .backOff { p.mouth = .tongue }
            return
        }
        switch social {
        case .greet, .approach:
            if bird { break }
            p.stance = dog ? .stand : .sit; p.tailUp = true
            if dog { p.tail = t * 9; p.mouth = .tongue }
        case .boop:
            let shut = k > 0.3 && k < 0.95
            p.eyes = shut ? .closed : .happy
            if species == .goose { p.headDX = 4; p.headDY = 9 }            // bends its long neck down to the other's nose
            else if bird { p.headDX = 2; p.headDY = 2 } else { p.stance = .stand; p.headDX = 1; p.tailUp = true; if dog { p.mouth = .closed; p.tail = t * 12 } }
        case .sniff:
            p.stance = .stand; p.headDX = 1; p.headDY = 2; p.eyes = .half; p.mouth = .closed; p.tail = t * 5
        case .wag:
            p.stance = .stand; p.eyes = .happy; p.tailUp = true
            if dog { p.tail = t * 16; p.mouth = .tongue }
        case .groom:
            let lick = Int(k / 0.3) % 2 == 0
            p.stance = .sit; p.tailUp = false; p.eyes = .closed
            p.headDX = lick ? 1 : 0; p.headDY = lick ? 1 : 0; p.mouth = lick ? .tongue : .closed
        case .groomed:
            p.stance = .sit; p.eyes = .happy; p.blush = true; p.tailUp = true; p.tail = t * 2; p.headDY = 1
        case .crouch where species == .redPanda && wiggling:
            // red pandas square up to play the way they square up to fight: up on the hind legs, forelimbs high
            p.stance = .upright; p.arm = .raised; p.phase = t * 9; p.eyes = .wide; p.tailUp = true
        case .crouch:
            p.stance = .crouch; p.eyes = .wide; p.tailUp = true; p.tail = t * 10; p.earsFlat = family == .cat
            if wiggling { p.wiggle = Int(t / 0.08) % 2 == 0 ? 1 : -1 }
            if dog { p.mouth = .tongue }
        case .pounce:
            p.stance = hopY > 0 ? .leap : .crouch; p.eyes = .wide; p.mouth = .open; p.earsFlat = family == .cat
        case .swat:
            let hit = Int((t + swatOffset) / 0.14) % 2 == 0
            p.stance = .upright; p.arm = hit ? .raised : .forward
            p.eyes = hit ? .wide : .closed; p.mouth = hit ? .open : .closed; p.headDX = hit ? 1 : 0
            p.earsFlat = family == .cat; p.tailUp = true; p.tail = t * 8
        case .hopBack:
            p.stance = hopY > 0 ? .leap : .stand; p.eyes = .wide; p.tailUp = true
            if dog { p.mouth = .tongue }
        case .bow:
            p.stance = .crouch; p.tailUp = true; p.tail = t * 18; p.eyes = .happy; p.mouth = dog ? .tongue : .open
            if k < 0.35 { p.mouth = .open }
        case .chase, .flee:
            p.stance = .stand; p.eyes = .happy; p.tailUp = true; if dog { p.mouth = .tongue }
        case .tagged:
            p.stance = .squash; p.eyes = .happy; p.mouth = .open
        case .pant:
            p.stance = .sit; p.eyes = .happy; p.bob = 0; p.tailUp = true; p.tail = t * 3
            p.mouth = Int(t / 0.2) % 2 == 0 ? (dog ? .tongue : .open) : .closed
        case .honk:
            p.mouth = Int(t / 0.1) % 2 == 0 ? .open : .closed; p.eyes = .angry; p.arm = flap ? .raised : .rest
            if species == .goose { p.headDX = 6; p.headDY = 8 } else { p.headDX = 2; p.headDY = 2 }
        case .proud:
            p.headDY = -3; p.eyes = k < 1.0 ? .closed : .open
            p.arm = k < 0.9 && Int(k / 0.2) % 2 == 0 ? .raised : .rest
            p.mouth = k < 0.4 ? .open : .closed
        case .startled where species == .redPanda:
            p.stance = .upright; p.arm = .raised; p.phase = t * 9; p.eyes = .wide; p.mouth = .open; p.tailUp = true
        case .startled:
            p.eyes = .wide; p.earsFlat = true; p.mouth = .open
            if bird { p.arm = flap ? .raised : .rest } else { p.stance = hopY > 0 ? .leap : .crouch; p.tailUp = true }
        case .scurry where family == .turtle:
            p.stance = .crouch; p.eyes = .wide                // stays tucked in its shell
        case .scurry:
            p.eyes = .wide; p.earsFlat = true
            if bird { p.headDY = -1 } else { p.stance = .stand; p.tailUp = false }
            if k < 0.6 { p.mouth = .open } else if dog { p.mouth = .closed }
        case .wary:
            p.stance = .crouch; p.headDX = 1; p.eyes = .wide; p.tailUp = false; p.tail = t * 3
        case .hiss where species == .redPanda:
            // its threat display: stands up tall, forelimbs above its head, a long stare and a huff
            p.stance = .upright; p.arm = .raised; p.phase = t * 9; p.eyes = .wide; p.tailUp = true
            p.mouth = k < 0.7 ? .open : .closed
        case .hiss:
            p.stance = .stand; p.earsFlat = true; p.eyes = .angry; p.tailUp = true
            p.mouth = k < 1.1 ? .open : .closed
            if k > 0.35 && k < 0.6 { p.arm = .raised }
        case .backOff:
            p.stance = .stand; p.earsFlat = true; p.eyes = .sad; p.tailUp = false; p.mouth = .closed
        case .blink:                                       // a cat's slow blink: "we're fine"
            p.stance = .sit; p.tailUp = true
            p.eyes = k < 0.4 ? .open : k < 0.7 ? .half : k < 1.3 ? .closed : k < 1.6 ? .half : .open
        case .snub:
            let lick = Int(k / 0.35) % 2 == 0
            p.stance = .sit; p.tailUp = false; p.eyes = .closed
            p.arm = lick ? .lick : .toMouth; p.mouth = lick ? .tongue : .closed
        case .confused:
            p.stance = .sit; p.tailUp = false; p.eyes = .open; p.tail = 0
            if dog { p.mouth = .closed }
        case .mimic:
            p.mouth = k < 1.0 && Int(k / 0.12) % 2 == 0 ? .open : .closed
            p.eyes = .happy; p.blush = species == .parrot; p.bob = Int(t / 0.2) % 2
            if bird { p.arm = k < 0.8 && flap ? .raised : .rest; p.headDX = 1 } else { p.stance = .sit }
        case .listen:
            p.eyes = .wide
            if bird { p.headDY = -1 } else { p.stance = .sit; p.tailUp = true; if dog { p.mouth = .closed } }
        case .speak:
            p.mouth = k < 0.5 ? .open : .closed; p.eyes = k < 0.5 ? .open : .happy
            if bird { p.arm = .raised } else { p.stance = .sit; p.tailUp = true }
        }
    }
}
