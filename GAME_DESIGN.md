# Wolverix - Werewolf Game Design Document

## Overview

Wolverix is a real-time multiplayer social deduction game based on the classic "Werewolf" (Mafia) party game. Players are secretly assigned roles and must use deduction, deception, and strategy to achieve their team's victory condition.

---

## Teams

### 🐺 Werewolves Team
- **Goal**: Eliminate all villagers (or reach numerical parity with villagers)
- **Knowledge**: Werewolves know each other's identities from the start
- **Communication**: Have a private voice/chat channel during night phase

### 🏠 Villagers Team
- **Goal**: Identify and eliminate all werewolves through voting
- **Knowledge**: Do not know anyone's role (except their own)
- **Communication**: Can only communicate during day phase in the main channel

### 💕 Lovers (Special)
- **Goal**: Survive together until the end (can override team goals)
- **Knowledge**: Lovers know each other's identity
- **Rule**: If one lover dies, the other dies immediately of heartbreak

---

## Roles

### Werewolf Team Roles

#### 🐺 Werewolf
- **Team**: Werewolves
- **Night Action**: Vote to kill one villager
- **Restrictions**:
  - Cannot target fellow werewolves
  - All werewolves vote together; majority decides the victim
  - Can change vote during night until phase ends
- **Visibility**: Sees other werewolves' identities

---

### Villager Team Roles

#### 👨‍🌾 Villager
- **Team**: Villagers
- **Night Action**: None (sleeps)
- **Special**: Basic role with no powers

#### 👁️ Seer (Voyante)
- **Team**: Villagers
- **Night Action**: Divine one player to learn if they are a Werewolf or not
- **Restrictions**:
  - Can only divine ONE player per night
  - Cannot divine the same player twice (they already know)
  - Action is mandatory each night
- **Result**: Learns "Werewolf" or "Not Werewolf"

#### 🧙‍♀️ Witch (Sorcière)
- **Team**: Villagers
- **Night Action**: Has TWO potions (one-time use each):
  1. **Heal Potion**: Save the werewolves' victim from death
  2. **Poison Potion**: Kill any player of her choice
- **Restrictions**:
  - Each potion can only be used ONCE per game
  - Can use both potions in the same night
  - Can see who the werewolves are targeting BEFORE deciding
  - Heal is automatic on current victim (no target selection needed)
  - Poison requires selecting a target
- **Critical Visibility**: During night, the Witch sees the provisional werewolf victim in real-time as werewolves vote

#### 🛡️ Bodyguard (Garde du Corps)
- **Team**: Villagers
- **Night Action**: Protect one player from werewolf attack
- **Restrictions**:
  - Cannot protect the SAME player two nights in a row
  - Can protect themselves
  - Protection only works against werewolf kills (not Witch poison)
- **Effect**: If protected player is attacked by werewolves, they survive

#### 🏹 Hunter (Chasseur)
- **Team**: Villagers
- **Trigger Action**: When the Hunter dies (by any cause), they MUST shoot one player
- **Restrictions**:
  - Shot is mandatory - cannot skip
  - Can shoot anyone (even already dead? No - must be alive)
  - Happens immediately upon death, interrupting normal flow
- **Effect**: The shot player dies immediately

#### 💘 Cupid (Cupidon)
- **Team**: Villagers (but lovers' survival can change this)
- **Night Action**: On the FIRST NIGHT ONLY, choose two players to become Lovers
- **Restrictions**:
  - Can only act on Night 0
  - Cannot change decision after submitting
  - Can choose themselves as one of the lovers
- **Effect**: The two chosen players become Lovers and know each other

#### 👑 Mayor (Maire) - Optional
- **Team**: Villagers
- **Day Action**: Can reveal themselves as Mayor
- **Effect**: Their vote counts as 2 during lynch voting
- **Restrictions**:
  - Once revealed, cannot hide again
  - Revealing is optional

---

## Game Phases

The game flows through a cycle of phases. Each phase has a specific duration configured by the room host.

### Phase Cycle

```
┌─────────────────────────────────────────────────────────┐
│                    GAME START                           │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                  NIGHT 0 (First Night)                  │
│  Duration: ~2 minutes                                   │
│  - Cupid chooses lovers (if present)                    │
│  - Werewolves vote on first victim                      │
│  - Seer divines first target                            │
│  - Bodyguard protects someone                           │
│  - Witch observes (usually doesn't act Night 0)         │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    DAY DISCUSSION                       │
│  Duration: ~5 minutes (configurable)                    │
│  - Announce night deaths (if any)                       │
│  - All alive players can speak                          │
│  - Players discuss and accuse                           │
│  - No voting yet                                        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    DAY VOTING                           │
│  Duration: ~1 minute (configurable)                     │
│  - Players vote to lynch one player                     │
│  - Can vote for anyone alive (including self)           │
│  - Can abstain (not vote)                               │
│  - Majority wins; ties = no lynch                       │
│  - Mayor's vote counts double if revealed               │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                 LYNCH RESOLUTION                        │
│  - If majority vote: player is lynched                  │
│  - Lynched player's role is revealed                    │
│  - If Hunter is lynched: Hunter shoots                  │
│  - Check win conditions                                 │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                      NIGHT N                            │
│  Duration: ~2 minutes (configurable)                    │
│  - Werewolves vote on victim                            │
│  - Seer divines                                         │
│  - Bodyguard protects (different from last night)       │
│  - Witch can heal or poison (if potions remain)         │
│  - Actions are SECRET - no one sees others acting       │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                 NIGHT RESOLUTION                        │
│  - Calculate final victim:                              │
│    • Werewolf target MINUS protected MINUS healed       │
│    • PLUS poisoned player                               │
│  - Dead players' roles revealed                         │
│  - If Hunter dies: Hunter shoots                        │
│  - Check win conditions                                 │
│  - If lovers die: both die                              │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
              (Loop back to DAY DISCUSSION)
```

---

## Voice & Chat Channel System

Communication is strictly controlled based on phase and role.

### During Night Phase

| Role | Voice Channel | Can Speak? | Can Hear? |
|------|---------------|------------|-----------|
| Werewolves | `werewolf` (private) | ✅ Yes | ✅ Only werewolves |
| All Others | `silence` (muted) | ❌ No | ❌ No |
| Dead Players | `dead` | ✅ Yes | ✅ Only dead |

### During Day Phase (Discussion & Voting)

| Role | Voice Channel | Can Speak? | Can Hear? |
|------|---------------|------------|-----------|
| All Alive | `main` | ✅ Yes | ✅ Everyone alive |
| Dead Players | `dead` | ✅ Yes (spectator) | ✅ Only dead |

### Channel Types
- **main**: Public channel for all alive players during day
- **werewolf**: Private channel for werewolves during night
- **dead**: Spectator channel for dead players (can't influence game)
- **spectator**: For non-players watching the game

---

## Action Validation Rules

### Night Actions

| Role | Required? | Can Skip? | Can Change? | Timing |
|------|-----------|-----------|-------------|--------|
| Werewolf Vote | Yes | No | Yes (until phase ends) | Any time during night |
| Seer Divine | Yes | No | No (once submitted) | Any time during night |
| Bodyguard Protect | Yes | No | No (once submitted) | Any time during night |
| Witch Heal | No | Yes | No (once used, gone forever) | After seeing victim |
| Witch Poison | No | Yes | No (once used, gone forever) | Any time during night |
| Cupid Choose | Yes (Night 0 only) | No | No (once submitted) | Night 0 only |

### Day Actions

| Action | Required? | Can Skip? | Can Change? |
|--------|-----------|-----------|-------------|
| Lynch Vote | No | Yes (abstain) | Yes (until phase ends) |
| Mayor Reveal | No | Yes | No (cannot un-reveal) |

---

## Death Resolution Order

When multiple deaths can occur, they are resolved in this order:

1. **Werewolf Kill** (can be prevented by Bodyguard or Witch Heal)
2. **Witch Poison** (cannot be prevented)
3. **Lynch** (cannot be prevented)
4. **Hunter Shot** (triggered by any of the above)
5. **Lover Heartbreak** (triggered by any death of a lover)

### Death Cascade Example
```
Werewolves kill Alice (who is a Lover with Bob)
  → Alice dies
  → Bob dies (heartbreak)
  → If Bob was the Hunter → Bob shoots Charlie
  → If Charlie was a Lover with Diana → Diana dies (heartbreak)
```

---

## Win Conditions

### Werewolves Win When:
- All villagers are dead, OR
- Werewolves equal or outnumber villagers

### Villagers Win When:
- All werewolves are dead

### Lovers Win When:
- Both lovers survive until another win condition is met
- If a Werewolf and a Villager are lovers, they form a third faction trying to eliminate everyone else

### Special Cases:
- If the last werewolf and last villager kill each other simultaneously → **Draw**
- If lovers are the last two alive → **Lovers Win**

---

## Real-Time Synchronization

### What Players See in Real-Time

#### Werewolves During Night:
- See each other's votes updating live
- See vote tally for each potential victim
- Can chat/voice with each other

#### Witch During Night:
- Sees the PROVISIONAL werewolf victim (who is winning the vote)
- This updates in real-time as werewolves change votes
- Can decide to heal based on current target

#### All Players During Day:
- See vote tally for lynch updating live
- See who voted for whom (public voting)
- Timer countdown to phase end

### What is Hidden:
- Other players' roles (unless conditions reveal them)
- Night action choices (who the Seer divined, etc.)
- Witch's potion status (has she used them?)
- Bodyguard's protection target

---

## Timer and Auto-Transitions

### Configurable Durations (Room Settings)
- `night_phase_seconds`: Default 120 (2 minutes)
- `day_phase_seconds`: Default 300 (5 minutes)
- `voting_seconds`: Default 60 (1 minute)

### Auto-Transition Behavior

When a phase timer expires:
1. **Night → Day**: Process all submitted actions, resolve deaths, start day
2. **Day Discussion → Day Voting**: Start the voting phase
3. **Day Voting → Night**: Tally votes, lynch if majority, start night

### Missing Actions at Phase End:
- **Werewolves**: If no majority, highest vote count wins (random if tie)
- **Seer**: If didn't divine, action is forfeit for this night
- **Bodyguard**: If didn't protect, no one is protected
- **Witch**: If didn't use potions, potions remain for later nights

---

## Game Configuration Options

### Player Count Requirements
- **Minimum**: 6 players
- **Maximum**: 16 players (configurable per room)

### Role Distribution (Recommended)
| Players | Werewolves | Special Roles |
|---------|------------|---------------|
| 6-7 | 2 | Seer, Witch |
| 8-9 | 2 | Seer, Witch, Bodyguard |
| 10-11 | 3 | Seer, Witch, Bodyguard, Hunter |
| 12+ | 3-4 | All roles including Cupid |

### Host Configurable Settings:
- Phase durations
- Which roles are included
- Number of werewolves
- Anonymous vs public voting
- Allow spectators

---

## Error States and Edge Cases

### What Happens If...

**All werewolves disconnect during night?**
→ Night proceeds, werewolves forfeit their kill

**A player disconnects mid-game?**
→ Player remains in game as "AFK", can reconnect
→ If timeout configured, player is removed and counts as dead

**Seer divines a Lover who is a Werewolf?**
→ Result shows "Werewolf" (Lover status doesn't hide role)

**Cupid chooses two Werewolves as Lovers?**
→ Valid! They are now Lovers but still on Werewolf team

**Witch tries to poison already-dead player?**
→ Action fails, poison is NOT consumed

**Bodyguard dies during the night they were protecting someone?**
→ Protection still applies for that night

**Hunter is poisoned and shot by werewolves same night?**
→ Hunter dies once, gets one shot (not two)

---

## State Machine Summary

```
GAME_STATES:
  - waiting     (room created, waiting for players)
  - starting    (countdown to game start)
  - active      (game in progress)
  - paused      (game paused by host)
  - finished    (game ended, winner determined)
  - abandoned   (game cancelled)

PHASE_STATES:
  - night_0          (first night)
  - night            (subsequent nights)
  - day_discussion   (day talking phase)
  - day_voting       (day voting phase)

PLAYER_STATES:
  - alive       (can act and vote)
  - dead        (spectator only)
  - disconnected (temporarily gone)
```

---

## Summary of Key Business Rules

1. **Werewolves know each other; villagers know nothing**
2. **Witch sees provisional victim in real-time during night**
3. **Bodyguard cannot protect same player twice in a row**
4. **Cupid only acts on Night 0**
5. **Hunter MUST shoot when dying - not optional**
6. **Lovers die together - always**
7. **Dead players can only observe, not influence**
8. **Phase timers are strict - actions must be submitted before timeout**
9. **Voting is public during day (everyone sees who votes for whom)**
10. **Night actions are private (no one knows what others did)**
