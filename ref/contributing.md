---
title: 'Contributing to the Gallformers Reference Library'
date: '2022-02-27'
author:
    name: Jeff Clark
description: How to contribute to the Gallformers Reference Library
---

If you would like to contribute to the Gallformers Reference Library it is quite easy. This article will describe the type of articles that we are looking for as well as the steps needed to get your article published.

## Types of Reference Material We Publish

We are primarily interested in publishing articles about galls. The types of content that we are currently looking for are:

- Guides to rearing adults from galls
- Beginners guide to finding galls
- Guides for host identifications
- Keys for complex groups
- Any original gall related research or findings

## Understanding How Your Article Will Be Licensed

Currently all original content that is published on the site is released under a [Creative Commons 4.0 Attribution License](https://creativecommons.org/licenses/by/4.0/). Attribution will refer to gallformers generally but most folks citing information want to give credit where credit is due and will include the specific author.

If you want to publish an article under a different license, [get in touch with us](mailto:gallformers@gmail.com) and we will see what we can do.

## Writing Your Article and Getting it Published

First you will need 2 things:

1. A [Github](https://github.com/) account
1. An understanding of [Markdown](https://www.markdownguide.org/getting-started)

### Writing

With these two steps complete you are ready to write! Write your article in whatever editor you choose. It is helpful, but not necessary, to use an editor that is markdown aware. You can also write it in another format, like MS Word or Google Docs, and then use one of the many online tools that will covert that format to markdown. Generally it is a good idea to stick to simple markdown as some of the various extensions to markdown will likely not render properly. If you are looking for a basic template you can view [this article's markdown source](https://github.com/jeffdc/gallformers/blob/main/ref/contributing.md).

#### Required Metadata

At the top of your article you must create a required metadata section that will contain the title, publishing date, author, and other info. I suggest copying this from this [article's source](https://github.com/jeffdc/gallformers/blob/main/ref/contributing.md). The metadata section must look like this:
```
---
title: 'The Title of Your Awesome Article'
date: '2022-02-27'
description: 'A short one sentence description of this article.'
author:
    name: Your Name
---
```

#### Limitations

Currently it is not possible to add hosted images to the article. You can link to images that are already published on the web, but please use this sparingly. We will eventually have the ability to publish images along with articles.

### Publishing

To get your article published you will open a Pull Request against the gallformers repository on Github. To do this, follow these steps:

1. Navigate to the [gallformers repository](https://github.com/jeffdc/gallformers) on Github
1. Make sure that you are logged in to Github
1. Click on the "Add File" button
1. Select "Create a New File"
    1. This will create a fork of the repository under your account and allow you to open a pull request
1. Name your file. This should be a short but descriptive title for your article. Please use all lowercase letters with no spaces or punctuation
1. Copy the source of your article and paste it into the "Edit New File" box
1. Click "Propose New File" at the bottom of the page
1. On the next screen click on "Create pull request"
1. In the comment section write any details that you want. These will seen by th reviewer and might be useful to describe why you think the article should be published on Gallformers
1. Click on "Create pull request"

At this point a Pull Request has been created. One of our reviewers will review the article. We may request changes to the article. We will do this via Github's review mechanism. You will be notified by email so make sure you have added Github to your address book so the messages do not end up lost in your spam folder.

Once the review process is done the article will go live on the site within a couple of hours.

### Future Edits

If for whatever reason in the future you want to update the article the process is straight-forward. 

1. Navigate to the article on Github. They are all in the [`ref`](https://github.com/jeffdc/gallformers/ref) directory 1. Once you have clicked on the article you want to edit, find the pencil icon in the toolbar above the article content and click on it
1. This will take you into an editor where you can make the changes
1. Once the changes are complete fill in a comment as to the nature of the changes that you made
1. Click on "Propose Changes"
1. On the next screen click on "Create pull request"

This will then trigger the review process which is the same as with the Publish step above.

## Closing Thoughts

We thank you for the articles that you write. The gallformers site would not exist without the hundreds of hours of volunteer time from our band of gall nerds. 
