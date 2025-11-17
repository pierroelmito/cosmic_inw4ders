package main

import "w4"

import "base:runtime"
import "core:math"
import "core:math/rand"

MaxXSpawns :: 9
MaxYSpawns :: 5
MaxSpawns :: MaxXSpawns * MaxYSpawns

makeSpawnData :: proc "c" () -> [MaxSpawns]i32 {
	r: [MaxSpawns]i32 = {}
	for i := 0; i < 3 * MaxSpawns / 4; i += 1 {
		r[i] = i32(i / 2)
	}
	return r
}

SpawnData: [MaxSpawns]i32

State :: enum {
	Menu,
	Game,
	Death,
	GameOver,
}

P :: 256

p :: #force_inline proc "c" (x: i32, y: i32) -> [2]i32 {
	return {x * P, y * P}
}
xy :: #force_inline proc "c" (p: [2]i32) -> (i32, i32) {
	return p[0] / P, p[1] / P
}

FreeList :: struct($Item: typeid, $Sz: u32) {
	items: [Sz]Item,
	count: u32,
}

PlayerShip :: struct {
	pos:   [2]i32,
	cd:    i32,
	sf:    i32,
	lifes: i32,
	dx:    i32,
}

EnemyShip :: struct {
	spawnPos:   [2]i32,
	startPos:   [2]i32,
	cpos:       [2]i32,
	hp:         i32,
	startFrame: i32,
	cd:         i32,
}

Bullet :: struct {
	pos:    [2]i32,
	speed:  [2]i32,
	active: bool,
}

Particle :: struct {
	pos:   [2]i32,
	speed: [2]i32,
	tl:    i32,
}

Game :: struct {
	state:      State,
	ship:       PlayerShip,
	enemies:    FreeList(EnemyShip, 64),
	pbullets:   FreeList(Bullet, 16),
	ebullets:   FreeList(Bullet, 256),
	hparticles: FreeList(Particle, 16),
	dparticles: FreeList(Particle, 16),
	frame:      i32,
	endFrame:   i32,
	wave:       i32,
	stars:      [40]i32,
}

g: Game

add :: proc "c" (fl: ^FreeList($Item, $Sz), i: Item) -> bool {
	if (fl^.count >= len(fl^.items)) do return false
	fl^.items[fl^.count] = i
	fl^.count += 1
	return true
}

all :: proc "c" (fl: ^FreeList($Item, $Sz)) -> []Item {
	return fl^.items[0:fl^.count]
}

reset :: proc "c" (fl: ^FreeList($Item, $Sz)) {
	fl^.count = 0
}

filter :: proc "c" (fl: ^FreeList($Item, $Sz), fn: proc "c" (_: ^Item) -> bool) {
	j: u32 = 0
	for i: u32 = 0; i < fl^.count; i += 1 {
		b := &fl^.items[i]
		ok := fn(b)
		if (ok) {
			if (j != i) do fl^.items[j] = fl^.items[i]
			j += 1
		}
	}
	fl^.count = j
}

setPalette :: proc "c" (f: u32) {
	c :: proc "c" (r, g, b: u32) -> u32 {
		return r << 16 | g << 8 | b
	}
	l :: proc "c" (v0: u32, v1: u32, f: u32) -> u32 {
		return (v0 * f + v1 * (256 - f)) / 256
	}

	R :: 0x00
	G :: 0x09
	B :: 0x49

	w4.PALETTE[0] = c(R, G, B)
	w4.PALETTE[1] = c(l(R, 0x00, f), l(G, 0x27, f), l(B, 0x68, f))
	w4.PALETTE[2] = c(l(R, 0x7b, f), l(G, 0xb3, f), l(B, 0x1c, f))
	w4.PALETTE[3] = c(l(R, 0xff, f), l(G, 0x88, f), l(B, 0x63, f))
}

@(export)
start :: proc "c" () {
	setPalette(0)
	setState(State.Menu)
	for &s, i in g.stars do s = i32(((33 * i + 12) * i + 24) * i + 13) % 220
	SpawnData = makeSpawnData()
}

setState :: proc "c" (s: State, f: i32 = 0) {
	g.frame = f
	g.state = s
}

outline :: proc "c" (t: cstring, x: i32, y: i32) {
	w4.DRAW_COLORS^ = 2
	w4.text(t, x - 1, y)
	w4.text(t, x + 1, y)
	w4.text(t, x, y - 1)
	w4.text(t, x, y + 1)
	w4.DRAW_COLORS^ = 4
	w4.text(t, x, y)
}

mpath :: proc "c" (spawn: [2]i32, start: [2]i32, f: i32) -> [2]i32 {
	o :: 25
	su :: 100
	if f < su {
		return spawn + f * (start - spawn) / su
	}
	x := (abs(((f - su) / 4 + o) % (4 * o) - 2 * o) - o) * P
	y := ((f - su) * P) / 10
	return start + {x, y}
}

spawn :: proc "c" () {
	context = runtime.default_context()
	rand.shuffle(SpawnData[:])
	g.wave += 1
	for sy := 0; sy < MaxYSpawns; sy += 1 {
		y := sy
		for sx := 0; sx < MaxXSpawns; sx += 1 {
			x := sx - 4
			if g.wave < i32(SpawnData[sy * MaxXSpawns + sx]) do continue
			pos := p(80 + i32(x) * 12, 8 + i32(y) * 12)
			dy: i32 = 100
			dx: i32 = -200 + rand.int31() % 400
			add(
				&g.enemies,
				EnemyShip {
					pos - p(dx, dy),
					pos,
					pos,
					3,
					g.frame,
					100 + (i32(y) * 10 + i32(x)) * 10,
				},
			)
		}
	}
}

make_hparticles :: proc "c" (pos: [2]i32, s: i32 = 1) {
	pf :: 16
	add(&g.hparticles, Particle{pos, p(0, 200 * s) / 300, pf})
	add(&g.hparticles, Particle{pos, p(-100, 100 * s) / 300, pf})
	add(&g.hparticles, Particle{pos, p(100, 100 * s) / 300, pf})
}

make_dparticles :: proc "c" (pos: [2]i32) {
	pf :: 12
	add(&g.dparticles, Particle{pos, p(0, 300) / 300, pf})
	add(&g.dparticles, Particle{pos, p(-200, 200) / 300, pf})
	add(&g.dparticles, Particle{pos, p(200, 200) / 300, pf})
	add(&g.dparticles, Particle{pos, p(0, -300) / 300, pf})
	add(&g.dparticles, Particle{pos, p(-200, -200) / 300, pf})
	add(&g.dparticles, Particle{pos, p(200, -200) / 300, pf})
}

drawStars :: proc "c" () {
	w4.DRAW_COLORS^ = 0x20
	w4.blit(&moon[0], 100, 10, moon_width, moon_height, moon_flags)
	w4.DRAW_COLORS^ = 2
	for s, i in g.stars {
		b := i % 2 == 0
		sz: i32 = b ? 60 : 10
		sp: i32 = b ? 7 : 2
		wi: u32 = b ? 2 : 1
		if i % 2 == 1 || (g.frame % 2) == 0 {
			w4.rect(i32(i * 4), (s + g.frame * sp) % 220 - sz, wi, u32(sz))
		}
	}
}

draw_ship :: proc "c" (o: ^PlayerShip) {
	if o.sf == 0 || g.frame & 2 == 0 {
		if o.dx == 0 {
			w4.blit(&ship0[0], xy(o.pos - p(4, 4)), ship0_width, ship0_height, ship0_flags)
		} else {
			f: w4.Blit_Flags = o.dx < 0 ? ship1_flags : ship1_flags | {.FLIPX}
			w4.blit(&ship1[0], xy(o.pos - p(4, 4)), ship1_width, ship1_height, f)
		}
	}
}

draw_enemy :: proc "c" (o: ^EnemyShip) {
	x, y := xy(o.cpos - p(4, 4))
	w4.blit(
		x & 8 == 0 ? &badguy0[0] : &badguy1[0],
		x,
		y,
		badguy0_width,
		badguy0_height,
		badguy0_flags,
	)
}

draw :: proc {
	draw_ship,
	draw_enemy,
}

update_ship :: proc "c" (o: ^PlayerShip) {
	if (o.cd > 0) do o.cd -= 1
	if (o.sf > 0) do o.sf -= 1
	shoot :: proc "c" (o: ^PlayerShip, dy: i32) {
		if (o.cd == 0 && g.pbullets.count < len(g.pbullets.items)) {
			o.cd = 14
			add(&g.pbullets, Bullet{o.pos - p(1, 0), p(0, dy), true})
			add(&g.pbullets, Bullet{o.pos + p(1, 0), p(0, dy), true})
		}
	}
	if .A in w4.GAMEPAD1^ do shoot(o, -3)
	else if .B in w4.GAMEPAD1^ do shoot(o, 3)
	{
		dx: i32 = 0
		dy: i32 = 0
		sx, sy := xy(o.pos)
		if .LEFT in w4.GAMEPAD1^ && sx > 0 do dx -= 1
		if .RIGHT in w4.GAMEPAD1^ && sx < 160 do dx += 1
		if .UP in w4.GAMEPAD1^ && sy > 0 do dy -= 1
		if .DOWN in w4.GAMEPAD1^ && sy < 160 do dy += 1
		o.dx = dx
		o.pos += p(dx, dy)
	}
}

update_gameplay :: proc "c" (playerAlive: bool) {
	context = runtime.default_context()

	gameOn := playerAlive && g.ship.lifes >= 0

	if (gameOn) {
		if g.enemies.count == 0 do spawn()

		update_ship(&g.ship)
		for &b in all(&g.ebullets) {
			d := g.ship.pos - b.pos
			if abs(d[0]) < 4 * P && abs(d[1]) < 4 * P {
				b.active = false
				if g.ship.sf == 0 {
					g.ship.sf = 32
					make_dparticles(g.ship.pos)
					if g.ship.lifes > 0 {
						g.ship.lifes -= 1
					} else {
						g.endFrame = g.frame + 255
						setState(State.Death, g.frame)
					}
				}
			}
		}
	}

	bulletsBB: [4]i32
	if (g.pbullets.count > 0) {
		bulletsBB[0] = g.pbullets.items[0].pos[0]
		bulletsBB[1] = g.pbullets.items[0].pos[1]
		bulletsBB[2] = g.pbullets.items[0].pos[0]
		bulletsBB[3] = g.pbullets.items[0].pos[1]
		for i: u32 = 1; i < g.pbullets.count; i += 1 {
			bulletsBB[0] = min(bulletsBB[0], g.pbullets.items[i].pos[0])
			bulletsBB[1] = min(bulletsBB[1], g.pbullets.items[i].pos[1])
			bulletsBB[2] = max(bulletsBB[2], g.pbullets.items[i].pos[0])
			bulletsBB[3] = max(bulletsBB[3], g.pbullets.items[i].pos[1])
		}
	}

	for &e in all(&g.enemies) {
		e.cpos = mpath(e.spawnPos, e.startPos, g.frame - e.startFrame)
		x, y := xy(e.cpos)
		if (y > 170) {
			e.startFrame = g.frame
			continue
		}
		if e.cd > 0 {
			e.cd -= 1
		} else {
			if gameOn {
				e.cd = 200
				rz :: 40
				r := p(rand.int31() % rz - rz / 2, rand.int31() % rz - rz / 2)
				d := (g.ship.pos + r - e.cpos) / 160
				l := math.sqrt(f32(d[0] * d[0] + d[1] * d[1]))
				c :: 260.0
				s: [2]i32 = {i32(f32(d[0]) * c / (1 + l)), i32(f32(d[1]) * c / (1 + l))}
				add(&g.ebullets, Bullet{e.cpos, s, true})
			}
		}
		if (g.pbullets.count > 0) {
			outside :=
				(bulletsBB[0] > e.cpos[0] + 4 * P) ||
				(bulletsBB[1] > e.cpos[1] + 4 * P) ||
				(bulletsBB[2] < e.cpos[0] - 4 * P) ||
				(bulletsBB[3] < e.cpos[1] - 4 * P)
			if !outside do for &b in all(&g.pbullets) {
				d := e.cpos - b.pos
				if abs(d[0]) < 4 * P && abs(d[1]) < 4 * P {
					e.hp -= 1
					b.active = false
					make_hparticles(b.pos, -b.speed[1] / abs(b.speed[1]))
					if e.hp == 0 {
						make_dparticles(e.cpos)
						break
					}
				}
			}
		}
	}

	fb := proc "c" (b: ^Bullet) -> bool {
		b.pos += b.speed
		return b.active && b.pos[0] > 0 && b.pos[1] > 0 && b.pos[0] < 160 * P && b.pos[1] < 160 * P
	}

	filter(&g.ebullets, fb)
	filter(&g.pbullets, fb)

	filter(&g.enemies, proc "c" (e: ^EnemyShip) -> bool {
		return e.hp > 0
	})

	updatep := proc "c" (p: ^Particle) -> bool {
		p.pos += p.speed
		p.tl -= 1
		return p.tl > 0
	}

	filter(&g.hparticles, updatep)
	filter(&g.dparticles, updatep)

	drawStars()
	w4.DRAW_COLORS^ = 3
	for p, i in all(&g.hparticles) do w4.rect(xy(p.pos), 1, 1)
	w4.DRAW_COLORS^ = 4
	for p, i in all(&g.dparticles) do w4.rect(xy(p.pos), 2, 2)
	w4.DRAW_COLORS^ = g.frame % 2 == 0 ? 2 : 3
	for &b in all(&g.pbullets) do w4.rect(xy(b.pos - p(0, 2)), 1, 4)
	w4.DRAW_COLORS^ = g.frame % 2 == 0 ? 2 : 4
	for &b in all(&g.ebullets) do w4.rect(xy(b.pos - p(1, 1)), 3, 3)
	w4.DRAW_COLORS^ = g.frame % 2 == 0 ? 3 : 4
	for &b in all(&g.ebullets) do w4.rect(xy(b.pos), 1, 1)
	w4.DRAW_COLORS^ = 0x4320
	for &e in all(&g.enemies) do draw(&e)
	w4.DRAW_COLORS^ = 0x4320
	if gameOn do draw(&g.ship)
	w4.DRAW_COLORS^ = 3
	for i in 0 ..< g.ship.lifes do w4.rect(5 + i * 4, 5, 3, 3)
}

update_game :: proc "c" () {
	update_gameplay(true)
}

update_death :: proc "c" () {
	if g.frame > g.endFrame {
		setPalette(0)
		setState(State.GameOver)
	} else {
		setPalette(255 - u32(g.endFrame - g.frame))
		update_gameplay(false)
	}
}

update_menu :: proc "c" () {
	if (g.frame <= 32) {
		setPalette(u32((32 - g.frame) * 8))
	}
	if .A in w4.GAMEPAD1^ {
		setState(State.Game)
		g.ship = PlayerShip{p(76, 150), 0, 0, 5, 0}
		g.wave = 0
		reset(&g.enemies)
		reset(&g.ebullets)
		reset(&g.pbullets)
		reset(&g.hparticles)
		reset(&g.dparticles)
	}
	drawStars()
	outline("Cosmic", 35, 42)
	outline("InW4ders", 70, 56)
	w4.DRAW_COLORS^ = 3
	if g.frame % 32 < 24 do w4.text("press \x80 to start", 16, 106)
}

update_gameover :: proc "c" () {
	nbFrames :: 300
	if (g.frame <= 32) {
		setPalette(u32((32 - g.frame) * 8))
	} else if (g.frame >= nbFrames - 32) {
		setPalette(u32((32 + g.frame - nbFrames) * 8))
	}
	if g.frame >= nbFrames do setState(State.Menu)
	drawStars()
	outline("Game Over", 44, 76)
}

@(export)
update :: proc "c" () {
	g.frame += 1
	switch g.state {
	case State.Menu:
		update_menu()
	case State.Game:
		update_game()
	case State.Death:
		update_death()
	case State.GameOver:
		update_gameover()
	}
}
