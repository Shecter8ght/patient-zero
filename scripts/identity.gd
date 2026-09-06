extends RefCounted
class_name Identity

const MALE_NAMES = [
	"Alexander", "Alexei", "Andrei", "Anton", "Artem", "Boris", "Vadim", "Vasily",
	"Viktor", "Vitaly", "Vladimir", "Vladislav", "Vyacheslav", "Gennady", "Georgy",
	"Grigory", "Dmitry", "Evgeny", "Ivan", "Igor", "Ilya", "Kirill", "Konstantin",
	"Leonid", "Maxim", "Mikhail", "Nikita", "Nikolai", "Oleg", "Pavel", "Pyotr",
	"Roman", "Ruslan", "Sergei", "Stepan", "Timur", "Fyodor", "Filipp", "Yuri", "Yakov",
	"Denis", "Yegor", "Zakhar", "Lev", "Mark", "Matvei", "Semyon", "Tikhon", "Eduard", "Anatoly"
]

const FEMALE_NAMES = [
	"Alexandra", "Alina", "Alisa", "Anastasia", "Anna", "Valentina", "Valeria",
	"Vera", "Viktoria", "Galina", "Daria", "Ekaterina", "Elena", "Zhanna", "Zinaida",
	"Irina", "Karina", "Kristina", "Ksenia", "Larisa", "Lyudmila", "Margarita",
	"Marina", "Maria", "Nadezhda", "Natalia", "Nina", "Oksana", "Olga", "Polina",
	"Svetlana", "Sofia", "Tamara", "Tatiana", "Yulia", "Yana", "Diana", "Lilia",
	"Regina", "Elina"
]

const LAST_NAMES_M = [
	"Ivanov", "Smirnov", "Kuznetsov", "Popov", "Vasiliev", "Petrov", "Sokolov",
	"Mikhailov", "Novikov", "Fedorov", "Morozov", "Volkov", "Alekseev", "Lebedev",
	"Semenov", "Egorov", "Pavlov", "Kozlov", "Stepanov", "Nikolaev", "Orlov",
	"Andreev", "Makarov", "Nikitin", "Zakharov", "Zaitsev", "Solovyov", "Borisov",
	"Yakovlev", "Grigoryev", "Romanov", "Vorobyov", "Sergeev", "Kuzmin", "Frolov",
	"Aleksandrov", "Dmitriev", "Korolyov", "Gusev", "Tikhonov", "Fomin", "Chernov",
	"Atamanov", "Belyaev", "Gromov", "Davydov", "Ershov", "Zhukov", "Zubov", "Kalinin"
]

const LAST_NAMES_F = [
	"Ivanova", "Smirnova", "Kuznetsova", "Popova", "Vasilieva", "Petrova", "Sokolova",
	"Mikhailova", "Novikova", "Fedorova", "Morozova", "Volkova", "Alekseeva", "Lebedeva",
	"Semenova", "Egorova", "Pavlova", "Kozlova", "Stepanova", "Nikolaeva", "Orlova",
	"Andreeva", "Makarova", "Nikitina", "Zakharova", "Zaitseva", "Solovyova", "Borisova",
	"Yakovleva", "Grigoryeva", "Romanova", "Vorobyova", "Sergeeva", "Kuzmina", "Frolova",
	"Aleksandrova", "Dmitrieva", "Korolyova", "Guseva", "Tikhonova", "Fomina", "Chernova",
	"Atamanova", "Belyaeva", "Gromova", "Davydova", "Ershova", "Zhukova", "Zubova", "Kalinina"
]

const OCCUPATIONS = [
	"bus driver", "accountant", "teacher", "doctor", "salesperson", "programmer",
	"builder", "cook", "security guard", "manager", "engineer", "nurse", "lawyer",
	"journalist", "plumber", "electrician", "warehouse worker", "dispatcher", "agronomist", "retiree",
	"student", "unemployed", "realtor", "notary", "pharmacist", "truck driver",
	"waiter", "hairdresser", "welder", "call center operator", "librarian",
	"mail carrier", "taxi driver", "janitor", "architect", "designer", "photographer",
	"psychologist", "social worker", "cashier", "installer", "foreman", "real estate agent",
	"tutor", "fitness trainer", "sysadmin", "veterinarian", "logistician",
	"animator", "official"
]

const TRAITS = [
	"loves cats", "binge-watches TV shows", "hates Mondays",
	"only drinks instant coffee", "always 5 minutes late",
	"collects fridge magnets", "afraid of heights", "sends voice messages",
	"dreams of a country house", "forgets to turn off the iron", "listens to radio in the car",
	"never eats soup", "believes in horoscopes", "reads mysteries before bed",
	"wants to lose weight since January", "proud of their car"
]

const LOCATIONS = [
	"near the mall entrance", "in the parking lot", "in the alley", "at the bus stop", "in the square",
	"by the fountain", "in the archway", "at the kiosk", "on the stairs", "near the bench"
]


static func generate(rng: RandomNumberGenerator, archetype: int, is_cop: bool) -> Dictionary:
	var male = rng.randi() % 2 == 0
	var first = ""
	var last  = ""
	if male:
		first = MALE_NAMES[rng.randi() % MALE_NAMES.size()]
		last  = LAST_NAMES_M[rng.randi() % LAST_NAMES_M.size()]
	else:
		first = FEMALE_NAMES[rng.randi() % FEMALE_NAMES.size()]
		last  = LAST_NAMES_F[rng.randi() % LAST_NAMES_F.size()]

	var age = rng.randi_range(20, 55)
	if archetype == 1:
		age = rng.randi_range(8, 15)
	elif archetype == 2:
		age = rng.randi_range(60, 80)
	elif archetype == 3:
		age = rng.randi_range(25, 45)
	if is_cop:
		age = rng.randi_range(25, 50)

	var occupation = ""
	if is_cop:
		occupation = "police officer"
	else:
		occupation = OCCUPATIONS[rng.randi() % OCCUPATIONS.size()]

	var ptrait = TRAITS[rng.randi() % TRAITS.size()]

	return {"first": first, "last": last, "age": age, "occupation": occupation, "trait": ptrait, "male": male}


static func full_name(d: Dictionary) -> String:
	return "%s %s" % [d["first"], d["last"]]


static func age_str(d: Dictionary) -> String:
	return "%d years" % int(d["age"])
