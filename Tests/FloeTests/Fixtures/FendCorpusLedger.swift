//
//  FendCorpusLedger.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//
//  Written by the replay suite when FLOE_WRITE_FEND_LEDGER=1. Do not add a line by hand.

/// Where Floe's calculator does not show what fend's own tests expect, one case to a line, with tabs
/// between: the kind of difference, the input, fend's answer and what Floe shows.
///
///   engine     the wrapper does not give fend's answer, so Floe cannot
///   not shown  fend answers and Floe shows no calculator
///   refused    Floe shows the calculator with an error, or empty
///   different  Floe shows something else
enum FendCorpusLedger {
    static let text = ##"""
    not shown	/sin (-pi/2)	-1	
    not shown	///sqrt! 16	approx. 0.0416666667	
    not shown	(x: sin^2 x + cos^2 x) 1	approx. 1	
    not shown	i	i	
    not shown	3i	3i	
    not shown	2i	2i	
    not shown	36#i i	36#i i	
    not shown	16#1 i	16#1 i	
    not shown	16#f i	16#f i	
    not shown	9#5i	9#5i	
    not shown	16#1e10	16#1e10	
    not shown	1kg	1 kg	
    not shown	1g	1 g	
    not shown	5 m	5 m	
    not shown	base	base	
    not shown	π	approx. 3.1415926536	
    not shown	τ	approx. 6.2831853072	
    not shown	dp	dp	
    not shown	10 dp	10 dp	
    not shown	float	float	
    not shown	fraction	fraction	
    not shown	auto	auto	
    not shown	/s	1 s^-1	
    not shown	per second	1 second^-1	
    not shown	(x: x) 1	1	
    not shown	(x: y: x) 1 2	1	
    not shown	(cis: (cis (pi/3))) (x: cos x + i * (sin x))	approx. 0.5 + 0.8660254038i	
    not shown	(x: iuwhe)	\\x.iuwhe	
    not shown	(addFive: addFive 4)(b: 5 + b)	9	
    not shown	(x: y: z: x) 1 2 3	1	
    not shown	(x: y: z: y) 1 2 3	2	
    not shown	(x: y: z: z) 1 2 3	3	
    not shown	(one: one + 4) 1	5	
    not shown	(one: one + one) 1	2	
    not shown	(x: x to kg) (5 g)	0.005 kg	
    not shown	(p: q: p p q) (x: y: y) (x: y: y) 1 0	0	
    not shown	(p: q: p p q) (x: y: y) (x: y: x) 1 0	1	
    not shown	(p: q: p p q) (x: y: x) (x: y: y) 1 0	1	
    not shown	(p: q: p p q) (x: y: x) (x: y: x) 1 0	1	
    not shown	(x => x) 1	1	
    not shown	(x: y => x) 1 2	1	
    not shown	(\\x. y => x) 1 2	1	
    not shown	a. => 0	a.:0	
    not shown	cis pi	-1	
    not shown	one	1	
    not shown	two	2	
    not shown	three	3	
    not shown	four	4	
    not shown	five	5	
    not shown	six	6	
    not shown	seven	7	
    not shown	eight	8	
    not shown	nine	9	
    not shown	ten	10	
    not shown	eleven	11	
    not shown	twelve	12	
    not shown	thirteen	13	
    not shown	fourteen	14	
    not shown	fifteen	15	
    not shown	sixteen	16	
    not shown	seventeen	17	
    not shown	eighteen	18	
    not shown	nineteen	19	
    not shown	twenty	20	
    not shown	thirty	30	
    not shown	forty	40	
    not shown	fifty	50	
    not shown	sixty	60	
    not shown	seventy	70	
    not shown	eighty	80	
    not shown	ninety	90	
    not shown	hundred	100	
    not shown	thousand	1000	
    not shown	million	1000000	
    not shown	dozen	12	
    not shown	one dozen	12	
    not shown	two dozen	24	
    not shown	three dozen	36	
    not shown	four dozen	48	
    not shown	five dozen	60	
    not shown	six dozen	72	
    not shown	seven dozen	84	
    not shown	eight dozen	96	
    not shown	nine dozen	108	
    not shown	ten dozen	120	
    not shown	eleven dozen	132	
    not shown	twelve dozen	144	
    not shown	gross	144	
    not shown	thirteen dozen	156	
    not shown	fourteen dozen	168	
    not shown	fifteen dozen	180	
    not shown	sixteen dozen	192	
    not shown	seventeen dozen	204	
    not shown	eighteen dozen	216	
    not shown	nineteen dozen	228	
    not shown	twenty dozen	240	
    not shown	thirty dozen	360	
    not shown	forty dozen	480	
    not shown	fifty dozen	600	
    not shown	sixty dozen	720	
    not shown	seventy dozen	840	
    not shown	eighty dozen	960	
    not shown	ninety dozen	1080	
    not shown	hundred dozen	1200	
    not shown	thousand dozen	12000	
    not shown	million dozen	12000000	
    not shown	yotta	1000000000000000000000000	
    not shown	zetta	1000000000000000000000	
    not shown	exa	1000000000000000000	
    not shown	peta	1000000000000000	
    not shown	tera	1000000000000	
    not shown	giga	1000000000	
    not shown	mega	1000000	
    not shown	myria	10000	
    not shown	kilo	1000	
    not shown	hecto	100	
    not shown	deca	10	
    not shown	deka	10	
    not shown	deci	0.1	
    not shown	centi	0.01	
    not shown	milli	0.001	
    not shown	micro	0.000001	
    not shown	nano	0.000000001	
    not shown	pico	0.000000000001	
    not shown	femto	0.000000000000001	
    not shown	atto	0.000000000000000001	
    not shown	zepto	0.000000000000000000001	
    not shown	yocto	0.000000000000000000000001	
    not shown	billion	1000000000	
    not shown	trillion	1000000000000	
    not shown	quadrillion	1000000000000000	
    not shown	quintillion	1000000000000000000	
    not shown	sextillion	1000000000000000000000	
    not shown	septillion	1000000000000000000000000	
    not shown	octillion	1000000000000000000000000000	
    not shown	nonillion	1000000000000000000000000000000	
    not shown	decillion	1000000000000000000000000000000000	
    not shown	undecillion	1000000000000000000000000000000000000	
    not shown	duodecillion	1000000000000000000000000000000000000000	
    not shown	tredecillion	1000000000000000000000000000000000000000000	
    not shown	quattuordecillion	1000000000000000000000000000000000000000000000	
    not shown	quindecillion	1000000000000000000000000000000000000000000000000	
    not shown	sexdecillion	1000000000000000000000000000000000000000000000000000	
    not shown	septendecillion	1000000000000000000000000000000000000000000000000000000	
    not shown	octodecillion	1000000000000000000000000000000000000000000000000000000000	
    not shown	novemdecillion	1000000000000000000000000000000000000000000000000000000000000	
    not shown	vigintillion	1000000000000000000000000000000000000000000000000000000000000000	
    engine	cent	1 cent	error
    engine	2 cent	2 cents	error
    not shown	sf	sf	
    not shown	1 sf	1 sf	
    not shown	10 sf	10 sf	
    not shown	quarter	0.25	
    not shown	@debug pi N	pi N (= 1000/1000 kilogram meter second^-2) (base 10, auto, simplifiable)	
    not shown	kg g	0.001 kg^2	
    not shown	eccentricity of earth	0.0167086	
    not shown	mass of earth	5972370000000000000000000 kg	
    engine	5% °C to °F	32.09 °F	error
    not shown	#""#		
    not shown	#"Hello, world!"#	Hello, world!	
    not shown	#"\\"#	\\	
    not shown	#"A quote: ""#	A quote: "	
    not shown	@debug #"hi"#	"hi"	
    not shown	@debug "hi"	"hi"	
    not shown	1 "	1"	
    not shown	""		
    not shown	"Hello, world!"	Hello, world!	
    not shown	"pi = " + (pi to string)	pi = approx. 3.1415926536	
    not shown	"\\a"	\x07	
    not shown	"\\f"	\x0c	
    not shown	" \\' "	 ' 	
    not shown	" hi \\z  \n\t  \r\n  ' \\z\\za\\z :"	 hi ' a:	
    not shown	'hi'	hi	
    not shown	'\\^?'	\x7f	
    engine	'\\^@'	\x00	
    not shown	'\\^['	\x1b	
    not shown	'\\^\\'	\x1c	
    not shown	'\\^]'	\x1d	
    not shown	'\\^^'	\x1e	
    not shown	'\\^_'	\x1f	
    not shown	'\\u{5}'	\x05	
    engine	'\\u{0}'	\x00	
    not shown	'\\u{1}'	\x01	
    not shown	'\\u{AAA}'	પ	
    engine	5 'pigeons' per meter / 'pigeons'	5 meters	error
    not shown	5k	5000	
    not shown	4 Metres	4 metres	
    not shown	4 mEtRes	4 metres	
    not shown	true	true	
    not shown	false	false	
    not shown	not true	false	
    not shown	not false	true	
    not shown	phi	approx. 1.6180339887	
    engine	$5	$5	error
    engine	$200/3 to 2dp	approx. $66.67	error
    engine	$3 * 7	$21	error
    engine	7 * $3	$21	error
    engine	£5 + £3	£8	error
    engine	¥5 + ¥3	¥8	error
    not shown	2; 4; 8kg; c:2c; a = 2	2	
    not shown	a = b = 2; b	2	
    not shown	a = 3; a = a + 4a; a	15	
    not shown	a = 3; b = 2a; c = a * b; c + a	21	
    not shown	d6	{ 1: 16.67%, 2: 16.67%, 3: 16.67%, 4: 16.67%, 5: 16.67%, 6: 16.67% }	
    not shown	2d6	{ 2: 2.78%, 3: 5.56%, 4: 8.33%, 5: 11.11%, 6: 13.89%, 7: 16.67%, 8: 13.89%, 9: 11.11%, 10: 8.33%, 11: 5.56%, 12: 2.78% }	
    not shown	()		
    not shown	;		
    not shown	;2;;3;a=4;;4a	16	
    not shown	;2;;3;a=4;;4a;;;()		
    not shown	planck	0.000000000000000000000000000000000662607015 J s	
    not shown	x:()	\\x.()	
    not shown	test_a = 5; test_a	5	
    not shown	5 KB	5 kB	
    not shown	5 Kb	5 kb	
    not shown	5 gb	5 Gb	
    not shown	5 kiwh	5 KiWh	
    not shown	partial_result = 2*(0.84 femto meter) / (1.35e-22 m/s^2); sqrt(partial_result)	approx. 3527.6684147528 s	
    not shown	1 + 2 == 3	true	
    not shown	1 + 2 != 4	true	
    not shown	true == false	false	
    not shown	true != false	true	
    not shown	true ≠ false	true	
    not shown	2m == 200cm	true	
    not shown	2kg == 200cm	false	
    not shown	2kg == true	false	
    not shown	2.010m == 200cm	false	
    not shown	2.000m == approx. 200cm	true	
    not shown	mean d1	1	
    not shown	mean d2	1.5	
    not shown	mean d500	250.5	
    not shown	mean (d1 + d1)	2	
    not shown	mean (d2 + d500)	252	
    not shown	mean (d6 / d2)	2.625	
    not shown	mean (d10 / d2)	4.125	
    not shown	average d500	250.5	
    """##
}
