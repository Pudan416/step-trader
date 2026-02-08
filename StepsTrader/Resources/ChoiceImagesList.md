# Список активностей для картинок (Choices)

Используй **id** как имя изображения в Assets (например `activity_favourite_sport` → `activity_favourite_sport.imageset`).

---

## Activity (9)

| id | title (EN) |
|----|------------|
| `activity_favourite_sport` | Doing my favourite sport |
| `activity_just_sports` | Just doing sports |
| `activity_apple_watch_3_rings` | Closing 3 Apple Watch rings |
| `activity_10k_steps` | Hitting 10k steps |
| `activity_hanging_bar` | Hanging from a bar |
| `activity_dancing` | Dancing alone or not alone |
| `activity_carrying_heavy` | Carrying something heavy |
| `activity_stairs` | Taking the stairs instead of the elevator |
| `activity_other` | Something else |

---

## Recovery (13)

| id | title (EN) |
|----|------------|
| `recovery_sleeping_well` | Sleeping well |
| `recovery_walking_mental` | Walking for mental health |
| `recovery_silence` | Sitting in silence |
| `recovery_hot_shower` | Taking a hot shower |
| `recovery_slow_breathing` | Slow breathing with closed eyes |
| `recovery_eating_healthy` | Eating as healthy as possible |
| `recovery_alone` | Being alone |
| `recovery_with_someone` | Being with someone |
| `recovery_good_talk` | Having a good talk |
| `recovery_fantasizing` | Fantasizing |
| `recovery_good_music` | Listening to good music |
| `recovery_resting` | Resting without a reason |
| `recovery_other` | Other |

---

## Joys (18)

| id | title (EN) |
|----|------------|
| `joys_favourite_hobby` | Doing a favourite hobby |
| `joys_whatever` | Doing whatever I feel like |
| `joys_drawing` | Drawing |
| `joys_great_time` | Having a great time |
| `joys_family` | Seeing my family |
| `joys_friends` | Being with friends |
| `joys_pet` | Playing with a pet |
| `joys_pizza` | Eating something tasty |
| `joys_singing` | Singing |
| `joys_something_fun` | Doing something fun |
| `joys_coffee_tea` | Drinking coffee or tea slowly |
| `joys_alcohol` | Drinking some alcohol |
| `joys_nothing` | Doing nothing on purpose |
| `joys_one_page` | Reading one page |
| `joys_pretty_picture` | Taking a pretty picture |
| `joys_bored` | Being bored |
| `joys_laughing` | Laughing at something stupid |
| `joys_other` | Other |

---

**Всего: 40 активностей** (9 + 13 + 18).

*Примечание:* В коде картинки для карточек сейчас выбираются по хешу от `option.id` из набора `refpic1`…`refpic7`. Чтобы показывать отдельную картинку для каждой активности, нужно будет привязать отображение к имени `option.id` (например `Image(option.id)` при наличии соответствующего assets).
