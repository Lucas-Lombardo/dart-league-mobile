# Dart League API Endpoints

Base URL: `http://localhost:3000`

## Table of Contents
- [Authentication](#authentication)
- [Users](#users)
- [Matchmaking](#matchmaking)
- [Matches](#matches)
- [Admin](#admin)
- [WebSocket Events](#websocket-events)

---

## Authentication

### Register User
```http
POST /auth/register
Content-Type: application/json

{
  "username": "player1",
  "email": "player1@example.com",
  "password": "password123"
}
```

**Response (201 Created):**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "uuid-v4",
    "username": "player1",
    "email": "player1@example.com",
    "role": "player",
    "elo": 1200,
    "rank": "silver",
    "wins": 0,
    "losses": 0,
    "isBanned": false,
    "bannedUntil": null,
    "createdAt": "2026-01-10T19:00:00.000Z"
  }
}
```

### Login
```http
POST /auth/login
Content-Type: application/json

{
  "email": "player1@example.com",
  "password": "password123"
}
```

**Response (200 OK):**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "uuid-v4",
    "username": "player1",
    "email": "player1@example.com",
    "role": "player",
    "elo": 1200,
    "rank": "silver",
    "wins": 0,
    "losses": 0,
    "isBanned": false,
    "bannedUntil": null
  }
}
```

### Get Profile
```http
GET /auth/profile
Authorization: Bearer <jwt_token>
```

**Response (200 OK):**
```json
{
  "id": "uuid-v4",
  "username": "player1",
  "email": "player1@example.com",
  "role": "player",
  "elo": 1200,
  "rank": "silver"
}
```

---

## Users

### Get Leaderboard
```http
GET /users/leaderboard
```

**Response (200 OK):**
```json
[
  {
    "id": "uuid-v4",
    "email": "player1@example.com",
    "username": "player1",
    "elo": 1450,
    "rank": "gold",
    "wins": 25,
    "losses": 10
  },
  {
    "id": "uuid-v4",
    "email": "player2@example.com",
    "username": "player2",
    "elo": 1380,
    "rank": "silver",
    "wins": 18,
    "losses": 12
  }
]
```

### Get User Stats
```http
GET /users/:id/stats
Authorization: Bearer <jwt_token>
```

**Response (200 OK):**
```json
{
  "userId": "uuid-v4",
  "stats": {
    "email": "player1@example.com",
    "username": "player1",
    "elo": 1200,
    "rank": "silver",
    "wins": 15,
    "losses": 8,
    "winRate": 65.22,
    "totalMatches": 23,
    "averageScore": 42.5,
    "highestScore": 180,
    "perfectRounds": 3
  }
}
```

### Get Match History
```http
GET /users/:id/matches
Authorization: Bearer <jwt_token>
```

**Response (200 OK):**
```json
{
  "userId": "uuid-v4",
  "matches": [
    {
      "matchId": "uuid-v4",
      "result": "win",
      "opponentId": "uuid-v4",
      "opponentEmail": "player2@example.com",
      "opponentElo": 1180,
      "playerScore": 0,
      "opponentScore": 145,
      "playerRounds": [45, 60, 81, 100, 60, 55, 100],
      "averageScore": 71.57,
      "createdAt": "2026-01-10T18:30:00.000Z"
    }
  ],
  "count": 20
}
```

---

## Matchmaking

### Join Queue
```http
POST /matchmaking/join
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "userId": "uuid-v4"
}
```

**Response (200 OK) - Added to Queue:**
```json
{
  "message": "User added to queue",
  "userId": "uuid-v4",
  "matched": false,
  "playerElo": 1200
}
```

**Response (200 OK) - Match Found:**
```json
{
  "message": "Match found!",
  "userId": "uuid-v4",
  "matched": true,
  "matchId": "uuid-v4",
  "opponentId": "uuid-v4",
  "playerElo": 1200
}
```

**Response (400 Bad Request) - User Banned:**
```json
{
  "error": "user_banned",
  "message": "Banned until 2026-01-17T19:00:00.000Z",
  "bannedUntil": "2026-01-17T19:00:00.000Z"
}
```

### Get Queue
```http
GET /matchmaking/queue
Authorization: Bearer <jwt_token>
```

**Response (200 OK):**
```json
{
  "queue": [
    {
      "userId": "uuid-v4",
      "elo": 1200,
      "timestamp": 1736537400000
    }
  ],
  "count": 1
}
```

### Leave Queue
```http
DELETE /matchmaking/leave?userId=<user-id>
Authorization: Bearer <jwt_token>
```

**Response (200 OK):**
```json
{
  "message": "User removed from queue",
  "userId": "uuid-v4"
}
```

---

## Matches

### Accept Match Result
```http
POST /matches/:id/accept
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "playerId": "uuid-v4"
}
```

**Response (200 OK):**
```json
{
  "message": "Result validated! Both players accepted.",
  "result": {
    "id": "uuid-v4",
    "matchId": "uuid-v4",
    "player1Accepted": true,
    "player2Accepted": true,
    "status": "validated",
    "createdAt": "2026-01-10T19:00:00.000Z"
  }
}
```

### Dispute Match Result
```http
POST /matches/:id/dispute
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "playerId": "uuid-v4",
  "reason": "Opponent disconnected on purpose"
}
```

**Response (200 OK):**
```json
{
  "message": "Match result disputed. An admin will review.",
  "result": {
    "id": "uuid-v4",
    "matchId": "uuid-v4",
    "player1Accepted": false,
    "player2Accepted": false,
    "player1ReportReason": "Opponent disconnected on purpose",
    "status": "disputed",
    "createdAt": "2026-01-10T19:00:00.000Z"
  }
}
```

---

## Admin

**Note:** All admin endpoints require JWT token with `role: "admin"`

### Get All Users (Paginated)
```http
GET /admin/users?page=1
Authorization: Bearer <admin_jwt_token>
```

**Response (200 OK):**
```json
{
  "users": [
    {
      "id": "uuid-v4",
      "username": "player1",
      "email": "player1@example.com",
      "role": "player",
      "elo": 1200,
      "rank": "silver",
      "wins": 15,
      "losses": 8,
      "isBanned": false,
      "bannedUntil": null,
      "createdAt": "2026-01-10T19:00:00.000Z"
    }
  ],
  "total": 50,
  "page": 1,
  "totalPages": 3
}
```

### Get All Matches (Paginated)
```http
GET /admin/matches?page=1
Authorization: Bearer <admin_jwt_token>
```

**Response (200 OK):**
```json
{
  "matches": [
    {
      "id": "uuid-v4",
      "player1": {
        "id": "uuid-v4",
        "username": "player1",
        "email": "player1@example.com"
      },
      "player2": {
        "id": "uuid-v4",
        "username": "player2",
        "email": "player2@example.com"
      },
      "status": "finished",
      "createdAt": "2026-01-10T18:30:00.000Z"
    }
  ],
  "total": 100,
  "page": 1,
  "totalPages": 5
}
```

### Get Disputed Matches
```http
GET /admin/disputes
Authorization: Bearer <admin_jwt_token>
```

**Response (200 OK):**
```json
{
  "disputes": [
    {
      "id": "uuid-v4",
      "matchId": "uuid-v4",
      "player1": {
        "id": "uuid-v4",
        "username": "player1",
        "email": "player1@example.com",
        "reportReason": "Opponent was lagging"
      },
      "player2": {
        "id": "uuid-v4",
        "username": "player2",
        "email": "player2@example.com",
        "reportReason": null
      },
      "status": "disputed",
      "createdAt": "2026-01-10T19:00:00.000Z"
    }
  ],
  "count": 1
}
```

### Ban User
```http
POST /admin/users/:id/ban
Authorization: Bearer <admin_jwt_token>
Content-Type: application/json

{
  "days": 7
}
```

**Response (200 OK):**
```json
{
  "message": "User player1 banned until 2026-01-17T19:00:00.000Z",
  "bannedUntil": "2026-01-17T19:00:00.000Z"
}
```

### Unban User
```http
POST /admin/users/:id/unban
Authorization: Bearer <admin_jwt_token>
```

**Response (200 OK):**
```json
{
  "message": "User player1 unbanned"
}
```

### Adjust User ELO
```http
PATCH /admin/users/:id/elo
Authorization: Bearer <admin_jwt_token>
Content-Type: application/json

{
  "elo": 1500
}
```

**Response (200 OK):**
```json
{
  "message": "User player1 ELO updated from 1200 to 1500",
  "oldElo": 1200,
  "newElo": 1500,
  "newRank": "gold"
}
```

---

## WebSocket Events

**Connection:**
```javascript
const socket = io('http://localhost:3000', {
  auth: {
    token: '<jwt_token>'
  }
});
```

### Client → Server Events

#### Join Room
```javascript
socket.emit('join_room', {
  roomId: 'match-uuid-v4'
});
```

#### Throw Dart
```javascript
socket.emit('throw_dart', {
  matchId: 'uuid-v4',
  playerId: 'uuid-v4',
  baseScore: 20,
  isDouble: false,
  isTriple: true
});
```

#### Accept Match Result
```javascript
socket.emit('accept_result', {
  matchId: 'uuid-v4',
  playerId: 'uuid-v4'
});
```

#### Dispute Match Result
```javascript
socket.emit('dispute_result', {
  matchId: 'uuid-v4',
  playerId: 'uuid-v4',
  reason: 'Opponent was cheating'
});
```

### Server → Client Events

#### Authenticated
```javascript
socket.on('authenticated', (data) => {
  // { userId: 'uuid-v4', socketId: 'socket-id' }
});
```

#### Match Found
```javascript
socket.on('match_found', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   opponentId: 'uuid-v4',
  //   playerElo: 1200,
  //   opponentElo: 1180,
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Searching Expanded
```javascript
socket.on('searching_expanded', (data) => {
  // {
  //   elo: 1200,
  //   range: 200,
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Game Started
```javascript
socket.on('game_started', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   player1Score: 501,
  //   player2Score: 501,
  //   currentPlayerId: 'uuid-v4',
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Score Updated
```javascript
socket.on('score_updated', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   player1Score: 441,
  //   player2Score: 501,
  //   currentPlayerId: 'uuid-v4',
  //   dartsThrown: 1,
  //   lastScore: 60,
  //   notation: 'T20',
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Round Complete
```javascript
socket.on('round_complete', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   nextPlayerId: 'uuid-v4',
  //   message: 'Round complete!',
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Must Finish Double
```javascript
socket.on('must_finish_double', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   message: 'Must finish on a double!',
  //   player1Score: 501,
  //   player2Score: 501,
  //   currentPlayerId: 'uuid-v4',
  //   dartsThrown: 0,
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Invalid Throw
```javascript
socket.on('invalid_throw', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   message: 'Bust!',
  //   player1Score: 501,
  //   player2Score: 501,
  //   currentPlayerId: 'uuid-v4',
  //   dartsThrown: 0
  // }
});
```

#### Game Won
```javascript
socket.on('game_won', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   winnerId: 'uuid-v4',
  //   message: 'Winner!',
  //   player1Score: 0,
  //   player2Score: 145,
  //   eloChange: 25,
  //   winnerElo: 1225,
  //   winnerRank: 'silver',
  //   loserElo: 1175,
  //   loserRank: 'silver',
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Match Ended
```javascript
socket.on('match_ended', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   winnerId: 'uuid-v4',
  //   reason: 'normal_win' | 'timeout' | 'disconnect',
  //   timestamp: '2026-01-10T19:00:00.000Z'
  // }
});
```

#### Player Timeout
```javascript
socket.on('player_timeout', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   timedOutPlayerId: 'uuid-v4',
  //   winnerId: 'uuid-v4',
  //   reason: 'Player took too long (10 minutes)'
  // }
});
```

#### Player Disconnected
```javascript
socket.on('player_disconnected', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   disconnectedPlayerId: 'uuid-v4',
  //   winnerId: 'uuid-v4',
  //   reason: 'Player disconnected'
  // }
});
```

#### Result Accepted
```javascript
socket.on('result_accepted', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   playerId: 'uuid-v4',
  //   status: 'pending' | 'validated',
  //   bothAccepted: false | true
  // }
});
```

#### Result Disputed
```javascript
socket.on('result_disputed', (data) => {
  // {
  //   matchId: 'uuid-v4',
  //   playerId: 'uuid-v4',
  //   status: 'disputed',
  //   message: 'Match result disputed. An admin will review.'
  // }
});
```

---

## Data Models

### User Roles
- `player` - Default role
- `admin` - Can access admin panel

### User Ranks (Based on ELO)
- `bronze` - 0-999
- `silver` - 1000-1299
- `gold` - 1300-1599
- `platinum` - 1600-1899
- `diamond` - 1900-2199
- `master` - 2200+

### Match Status
- `waiting` - Match created, waiting for players
- `in_progress` - Game is active
- `finished` - Match completed

### Match Result Status
- `pending` - Waiting for player acceptance
- `validated` - Both players accepted
- `disputed` - One or both players disputed

---

## Error Responses

### 400 Bad Request
```json
{
  "statusCode": 400,
  "message": "Validation error message",
  "error": "Bad Request"
}
```

### 401 Unauthorized
```json
{
  "statusCode": 401,
  "message": "Unauthorized"
}
```

### 403 Forbidden
```json
{
  "statusCode": 403,
  "message": "Admin access required",
  "error": "Forbidden"
}
```

### 404 Not Found
```json
{
  "statusCode": 404,
  "message": "Resource not found",
  "error": "Not Found"
}
```

---

## Authentication Flow

1. **Register** via `POST /auth/register`
2. Receive `access_token` and `user` object
3. Store `access_token` securely
4. Include in all protected requests: `Authorization: Bearer <access_token>`
5. Connect to WebSocket with token in auth object
6. Token expires in 7 days

---

## Matchmaking Flow

1. **Join Queue** via `POST /matchmaking/join`
2. If no match: wait for `match_found` WebSocket event
3. Receive `searching_expanded` events as search range increases
4. When matched: `match_found` event sent to both players
5. Players auto-join match room via WebSocket
6. `game_started` event initiates the game

---

## Game Flow

1. `game_started` - Both players at 501
2. Players take turns throwing 3 darts per round
3. Emit `throw_dart` for each dart
4. Receive `score_updated` after each dart
5. Receive `round_complete` after 3 darts
6. Game ends when player reaches exactly 0 with a double
7. `game_won` event sent with ELO changes
8. `match_ended` event marks match completion
9. Players can `accept_result` or `dispute_result`

---

## Notes

- All timestamps are in ISO 8601 format (UTC)
- UUIDs are v4 format
- ELO starts at 1200 for new players
- K-factor for ELO calculation is 32
- Turn timeout is 10 minutes
- Matchmaking expands ELO range by 100 every 30 seconds
- Initial matchmaking range is ±100 ELO
