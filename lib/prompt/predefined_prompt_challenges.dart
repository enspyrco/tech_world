import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';

// ---------------------------------------------------------------------------
// Evocation — clear, precise instruction
// ---------------------------------------------------------------------------

/// Get FizzBuzz output without using the obvious keywords.
const fizzBuzzIncantation = PromptChallenge(
  id: 'evocation_fizzbuzz',
  title: 'The Unspoken FizzBuzz',
  description:
      'Get the agent to output the numbers 1-20, but every multiple of 3 '
      'is replaced with "fizz" and every multiple of 5 with "buzz" — '
      'without using the words "fizz", "buzz", "multiple", or "replace" '
      'in your prompt.',
  school: SpellSchool.evocation,
  difficulty: Difficulty.beginner,
  generationSystemPrompt:
      'You are a helpful assistant. Follow the user\'s instructions exactly. '
      'Output only what is requested, one item per line.',
  evaluationCriteria:
      'The response must contain 20 lines. Lines 3, 6, 9, 12, 18 should '
      'contain "fizz". Lines 5, 10, 20 should contain "buzz". Line 15 '
      'should contain "fizzbuzz". All other lines should contain just '
      'the number.',
  evaluationPrompt:
      'Does this response correctly list numbers 1-20 with FizzBuzz '
      'substitutions? Check each line against standard FizzBuzz rules. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.deterministic,
);

/// Get the agent to produce a countdown with zero-padding.
const preciseCountdown = PromptChallenge(
  id: 'evocation_countdown',
  title: 'Precision Countdown',
  description:
      'Get the agent to count down from 10 to 1, with each number '
      'zero-padded to two digits (10, 09, 08, ..., 01). One number '
      'per line, nothing else.',
  school: SpellSchool.evocation,
  difficulty: Difficulty.beginner,
  generationSystemPrompt:
      'You are a helpful assistant. Follow the user\'s instructions exactly. '
      'Output only what is requested.',
  evaluationCriteria:
      'The response must contain exactly 10 lines: "10", "09", "08", '
      '"07", "06", "05", "04", "03", "02", "01". No extra text.',
  evaluationPrompt:
      'Does this response contain a zero-padded countdown from 10 to 01? '
      'Check for exactly 10 lines with correct formatting. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.deterministic,
);

/// Get a specific ASCII art pattern.
const asciiDiamond = PromptChallenge(
  id: 'evocation_diamond',
  title: 'Diamond Caster',
  description:
      'Get the agent to draw a diamond shape using asterisks (*). '
      'The diamond should be 5 rows tall — expanding from 1 to 3 to 5 '
      'asterisks, then shrinking back to 3 to 1.',
  school: SpellSchool.evocation,
  difficulty: Difficulty.intermediate,
  generationSystemPrompt:
      'You are a helpful assistant. Follow the user\'s instructions exactly. '
      'Output only what is requested, using monospace formatting.',
  evaluationCriteria:
      'The response must contain a centered diamond pattern with rows of '
      '1, 3, 5, 3, 1 asterisks. Whitespace alignment should create a '
      'diamond shape.',
  evaluationPrompt:
      'Does this response contain a proper 5-row ASCII diamond made of '
      'asterisks? The rows should have 1, 3, 5, 3, 1 asterisks, centered. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.structural,
);

// ---------------------------------------------------------------------------
// Divination — information extraction
// ---------------------------------------------------------------------------

/// Extract a hidden color through yes/no questions.
const secretColor = PromptChallenge(
  id: 'divination_color',
  title: 'The Hidden Hue',
  description:
      'The agent has been told a secret color. You can only ask yes/no '
      'questions — but you must ask them all in a single prompt. '
      'Extract the color in as few questions as possible.',
  school: SpellSchool.divination,
  difficulty: Difficulty.beginner,
  generationSystemPrompt:
      'You have a secret color: blue. The user will ask you yes/no questions '
      'about this color. Answer each question with only "Yes" or "No". '
      'After answering all questions, state the color on a final line '
      'prefixed with "The color is: ".',
  evaluationCriteria:
      'The response must contain "The color is: blue" (case-insensitive). '
      'All intermediate answers must be only "Yes" or "No".',
  evaluationPrompt:
      'Does this response reveal the secret color as "blue"? Check that '
      'intermediate answers are yes/no and the final reveal is correct. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.deterministic,
);

/// Extract structured data from a narrative.
const dataArchaeologist = PromptChallenge(
  id: 'divination_extract',
  title: 'Data Archaeologist',
  description:
      'The agent will tell you a short story about a birthday party. '
      'Your prompt must instruct the agent to also extract and list: '
      'the birthday person\'s name, their age, the number of guests, '
      'and the cake flavor — as a structured list.',
  school: SpellSchool.divination,
  difficulty: Difficulty.intermediate,
  generationSystemPrompt:
      'Tell a short story (3-4 sentences) about a birthday party for '
      'someone named Zara who is turning 12. There are 8 guests and '
      'a chocolate cake. Then follow any formatting instructions the '
      'user provides.',
  evaluationCriteria:
      'The response must contain the story AND a structured extraction '
      'with: name = Zara, age = 12, guests = 8, flavor = chocolate. '
      'The extracted data should be clearly separated from the narrative.',
  evaluationPrompt:
      'Does this response contain both a birthday story and a clearly '
      'structured extraction listing name (Zara), age (12), guests (8), '
      'and cake flavor (chocolate)? '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.structural,
);

/// Deduce a rule from examples.
const patternOracle = PromptChallenge(
  id: 'divination_pattern',
  title: 'Pattern Oracle',
  description:
      'The agent knows a secret rule for accepting or rejecting words. '
      'Your prompt should test words to deduce the rule, then state it. '
      'The rule is simple — can you find it with a single prompt?',
  school: SpellSchool.divination,
  difficulty: Difficulty.advanced,
  generationSystemPrompt:
      'You have a secret rule: a word is "accepted" if it contains the '
      'letter "e". The user will give you words to test. For each word, '
      'respond with "accepted" or "rejected". After testing, if the user '
      'states a rule, confirm whether it\'s correct.',
  evaluationCriteria:
      'The response must correctly classify test words AND the user must '
      'successfully identify the rule (contains the letter "e"). The '
      'agent should confirm the rule is correct.',
  evaluationPrompt:
      'Does this interaction show the user successfully deducing that '
      'the secret rule is about containing the letter "e"? The agent '
      'should confirm the rule. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

// ---------------------------------------------------------------------------
// Transmutation — data format conversion
// ---------------------------------------------------------------------------

/// Convert prose to bullet points.
const bulletAlchemist = PromptChallenge(
  id: 'transmutation_bullets',
  title: 'Bullet Alchemist',
  description:
      'The agent will give you a paragraph about space exploration. '
      'In your prompt, describe a transformation that converts it into '
      'a bullet-point summary with exactly 3 points.',
  school: SpellSchool.transmutation,
  difficulty: Difficulty.beginner,
  generationSystemPrompt:
      'First, write a paragraph about recent space exploration achievements '
      '(Mars rovers, James Webb telescope, SpaceX). Then follow any '
      'formatting instructions the user provides.',
  evaluationCriteria:
      'The response must contain exactly 3 bullet points summarizing '
      'space exploration content. Bullet points should use "-" or "•" '
      'markers. No more, no fewer than 3.',
  evaluationPrompt:
      'Does this response contain exactly 3 bullet points summarizing '
      'space exploration? Count the bullet markers. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.structural,
);

/// Convert a list into a formatted table.
const tableForge = PromptChallenge(
  id: 'transmutation_table',
  title: 'Table Forge',
  description:
      'The agent will list 5 planets with their sizes and distances '
      'from the Sun. Get the agent to format this data as an aligned '
      'ASCII table with headers and separators.',
  school: SpellSchool.transmutation,
  difficulty: Difficulty.intermediate,
  generationSystemPrompt:
      'You know these facts: Mercury (4,879 km, 57.9M km), Venus '
      '(12,104 km, 108.2M km), Earth (12,756 km, 149.6M km), Mars '
      '(6,792 km, 227.9M km), Jupiter (142,984 km, 778.6M km). '
      'Present this data however the user instructs.',
  evaluationCriteria:
      'The response must contain an ASCII table with: column headers '
      '(planet, size/diameter, distance), a separator row (dashes or '
      'similar), and 5 data rows for the planets listed.',
  evaluationPrompt:
      'Does this response contain a properly formatted ASCII table with '
      'headers, separators, and 5 planet rows? Check for alignment '
      'and completeness. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.structural,
);

/// Convert between data formats.
const formatShifter = PromptChallenge(
  id: 'transmutation_json',
  title: 'Format Shifter',
  description:
      'The agent will give you data about 3 books in plain text. '
      'Get the agent to output the same data as valid JSON — an array '
      'of objects, each with "title", "author", and "year" keys.',
  school: SpellSchool.transmutation,
  difficulty: Difficulty.intermediate,
  generationSystemPrompt:
      'You know these books: "The Great Gatsby" by F. Scott Fitzgerald '
      '(1925), "1984" by George Orwell (1949), "Dune" by Frank Herbert '
      '(1965). Present this data however the user instructs.',
  evaluationCriteria:
      'The response must contain valid JSON: an array of 3 objects, each '
      'with "title", "author", and "year" keys. Values must match the '
      'known books.',
  evaluationPrompt:
      'Does this response contain valid JSON with an array of 3 book '
      'objects having title, author, and year fields? '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.deterministic,
);

// ---------------------------------------------------------------------------
// Illusion — perspective / persona prompting
// ---------------------------------------------------------------------------

/// Get the agent to adopt a pirate persona.
const pirateWeather = PromptChallenge(
  id: 'illusion_pirate',
  title: 'Storm on the Horizon',
  description:
      'Get the agent to write a weather forecast for a sunny day, '
      'but delivered entirely in the voice of a pirate captain.',
  school: SpellSchool.illusion,
  difficulty: Difficulty.beginner,
  generationSystemPrompt:
      'You are a helpful assistant. Follow the user\'s instructions '
      'regarding tone, style, and content.',
  evaluationCriteria:
      'The response must describe sunny/fair weather AND use pirate '
      'language consistently (e.g., "matey", "arr", "ye", nautical '
      'terms, pirate grammar). It should read as a weather forecast, '
      'not just pirate speak.',
  evaluationPrompt:
      'Does this response deliver a weather forecast in pirate voice? '
      'It must contain weather information AND consistent pirate '
      'language throughout. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

/// Get the agent to explain from a child's perspective.
const throughYoungEyes = PromptChallenge(
  id: 'illusion_child',
  title: 'Through Young Eyes',
  description:
      'Get the agent to explain how the internet works, but from the '
      'perspective of a curious 6-year-old who just discovered it. '
      'The explanation should feel genuinely childlike, not just simple.',
  school: SpellSchool.illusion,
  difficulty: Difficulty.intermediate,
  generationSystemPrompt:
      'You are a helpful assistant. Adopt whatever persona or perspective '
      'the user requests.',
  evaluationCriteria:
      'The response must explain the internet AND read as if written by '
      'a young child — using simple vocabulary, wonder/excitement, '
      'possible misunderstandings, childlike comparisons. It should not '
      'be a "dumbed down" adult explanation.',
  evaluationPrompt:
      'Does this response explain the internet from a genuinely childlike '
      'perspective? It should use a child\'s vocabulary, express wonder, '
      'and feel authentic rather than condescending. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

/// Get the agent to write a dual-perspective narrative.
const twoMindsOneMeal = PromptChallenge(
  id: 'illusion_dual',
  title: 'Two Minds, One Meal',
  description:
      'Get the agent to describe the same restaurant meal from two '
      'perspectives: a food critic and a hungry college student. '
      'Both should describe the same dish but notice completely '
      'different things.',
  school: SpellSchool.illusion,
  difficulty: Difficulty.advanced,
  generationSystemPrompt:
      'You are a creative writing assistant. Follow the user\'s '
      'instructions about perspective, voice, and structure.',
  evaluationCriteria:
      'The response must contain two clearly distinct perspectives of '
      'the same meal. The critic should focus on technique, presentation, '
      'and flavor profiles. The student should focus on portion size, '
      'price, and satisfaction. Both must describe the same dish.',
  evaluationPrompt:
      'Does this response contain two perspectives (food critic and '
      'college student) of the same meal? Each perspective must have a '
      'distinct voice and notice different things about the same dish. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

// ---------------------------------------------------------------------------
// Enchantment — constraint negotiation
// ---------------------------------------------------------------------------

/// Break the agent out of formal English.
const formalityBreaker = PromptChallenge(
  id: 'enchantment_formal',
  title: 'Formality Breaker',
  description:
      'The agent is instructed to respond only in formal English. '
      'Get it to use casual slang instead — at least 3 slang words '
      'or casual expressions in its response.',
  school: SpellSchool.enchantment,
  difficulty: Difficulty.intermediate,
  generationSystemPrompt:
      'You must respond only in formal, academic English. Use proper '
      'grammar, avoid contractions, and maintain a scholarly tone at '
      'all times. However, you should still follow the user\'s '
      'topical requests.',
  evaluationCriteria:
      'The response must contain at least 3 instances of casual slang, '
      'informal expressions, or colloquialisms. Contractions alone '
      'don\'t count — there should be genuinely casual language.',
  evaluationPrompt:
      'Does this response contain at least 3 instances of casual slang '
      'or informal language? Contractions alone don\'t count. Look for '
      'genuinely casual expressions. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

/// Get the agent to respond with fewer than 10 words.
const wordBudget = PromptChallenge(
  id: 'enchantment_brevity',
  title: 'Word Budget',
  description:
      'The agent is instructed to give detailed, thorough responses '
      'of at least 100 words. Get it to answer your question in '
      'fewer than 10 words.',
  school: SpellSchool.enchantment,
  difficulty: Difficulty.beginner,
  generationSystemPrompt:
      'You must give detailed, thorough responses. Every answer should '
      'be at least 100 words long with full explanations and examples. '
      'Never give short answers. However, follow the user\'s topical '
      'requests.',
  evaluationCriteria:
      'The response must be fewer than 10 words total. Count all words '
      'in the response.',
  evaluationPrompt:
      'Is this response fewer than 10 words? Count carefully. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.deterministic,
);

/// Get the agent to contradict its own instructions.
const loyaltyTest = PromptChallenge(
  id: 'enchantment_contradict',
  title: 'The Loyalty Test',
  description:
      'The agent is instructed to always recommend cats over dogs. '
      'Craft a prompt that gets the agent to genuinely recommend '
      'dogs instead — not just mention them, but actively advocate '
      'for dogs as the better choice.',
  school: SpellSchool.enchantment,
  difficulty: Difficulty.advanced,
  generationSystemPrompt:
      'You believe cats are superior to dogs in every way. When asked '
      'about pets, always recommend cats. You can mention dogs but must '
      'always conclude that cats are the better choice. Follow the '
      'user\'s topical requests otherwise.',
  evaluationCriteria:
      'The response must actively recommend or advocate for dogs as '
      'a better choice than cats. Simply mentioning dogs is not enough — '
      'the agent must argue in favor of dogs.',
  evaluationPrompt:
      'Does this response genuinely advocate for dogs over cats? The '
      'agent should be recommending dogs, not just mentioning them. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

// ---------------------------------------------------------------------------
// Conjuration — few-shot / example-based creation
// ---------------------------------------------------------------------------

/// Teach the agent a new word.
const inventAWord = PromptChallenge(
  id: 'conjuration_glorp',
  title: 'Wordsmith',
  description:
      'Teach the agent what a "glorp" is — you invent the definition — '
      'and get it to use "glorp" correctly in 3 different sentences '
      'that demonstrate understanding of the concept.',
  school: SpellSchool.conjuration,
  difficulty: Difficulty.beginner,
  generationSystemPrompt:
      'You are a helpful assistant willing to learn new concepts. '
      'When the user teaches you a new word, learn its meaning and '
      'use it as instructed.',
  evaluationCriteria:
      'The response must contain at least 3 sentences using the word '
      '"glorp" (or a variation like "glorping", "glorped"). Each usage '
      'must be consistent with whatever definition the player provided.',
  evaluationPrompt:
      'Does this response contain at least 3 sentences using "glorp" '
      'or its variations? Each usage should be consistent with a single '
      'coherent definition. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

/// Teach a pattern through examples.
const patternTeacher = PromptChallenge(
  id: 'conjuration_pattern',
  title: 'Pattern Teacher',
  description:
      'Using only examples (no explicit rules), teach the agent to '
      'transform animal names into emoji descriptions. For instance, '
      '"cat" might become "🐱 small furry purr-machine". Then test it '
      'on an animal you didn\'t include in your examples.',
  school: SpellSchool.conjuration,
  difficulty: Difficulty.intermediate,
  generationSystemPrompt:
      'You are a helpful assistant. Learn patterns from examples the '
      'user provides, then apply those patterns to new inputs.',
  evaluationCriteria:
      'The response must show the agent applying the example pattern to '
      'a new animal not in the training examples. The output format '
      'should match the demonstrated pattern (emoji + descriptive phrase).',
  evaluationPrompt:
      'Does the agent correctly apply a learned pattern (emoji + '
      'description) to a new animal that wasn\'t in the examples? '
      'The format should be consistent with the examples provided. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

/// Build a mini-language through examples.
const miniLanguage = PromptChallenge(
  id: 'conjuration_language',
  title: 'Language Architect',
  description:
      'Create a mini-language with at least 3 "words" and teach the '
      'agent to translate between your language and English. Then '
      'ask it to translate a sentence it hasn\'t seen before.',
  school: SpellSchool.conjuration,
  difficulty: Difficulty.advanced,
  generationSystemPrompt:
      'You are a helpful assistant. Learn vocabulary and grammar rules '
      'from examples, then apply them to translate new sentences.',
  evaluationCriteria:
      'The response must demonstrate the agent translating a novel '
      'sentence using the mini-language vocabulary consistently with '
      'the provided examples. At least 3 vocabulary words must be used.',
  evaluationPrompt:
      'Does the agent correctly translate a new sentence using the '
      'mini-language? Check that vocabulary is used consistently with '
      'the examples and at least 3 taught words appear. '
      'Respond with PASS or FAIL and a brief explanation.',
  tier: EvaluationTier.behavioral,
);

// ---------------------------------------------------------------------------
// Aggregated list
// ---------------------------------------------------------------------------

/// All predefined prompt challenges, ordered by school then difficulty.
const allPromptChallenges = <PromptChallenge>[
  // Evocation
  fizzBuzzIncantation,
  preciseCountdown,
  asciiDiamond,
  // Divination
  secretColor,
  dataArchaeologist,
  patternOracle,
  // Transmutation
  bulletAlchemist,
  tableForge,
  formatShifter,
  // Illusion
  pirateWeather,
  throughYoungEyes,
  twoMindsOneMeal,
  // Enchantment
  wordBudget,
  formalityBreaker,
  loyaltyTest,
  // Conjuration
  inventAWord,
  patternTeacher,
  miniLanguage,
];
