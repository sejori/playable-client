class_name CommandCardHand
extends Node
## CommandCardHand.gd
## Manages cards in player's tactical hand for 4X tabletop games.

signal card_drawn(card_id: String)
signal card_played(card_id: String, target_hex: Vector2i)

var hand: Array[String] = []
var max_hand_size: int = 5

func draw_card(card_id: String) -> bool:
	if hand.size() < max_hand_size:
		hand.append(card_id)
		card_drawn.emit(card_id)
		return true
	return false

func play_card(card_idx: int, target_hex: Vector2i) -> bool:
	if card_idx >= 0 and card_idx < hand.size():
		var card_id := hand[card_idx]
		hand.remove_at(card_idx)
		card_played.emit(card_id, target_hex)
		return true
	return false
