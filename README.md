# hardened-wordpress
A website that can modify its own PHP files, although cool, is an exploit just waiting to happen.

This is a collection of shell scripts and apache .htaccess files to help you disable Wordpress's ability to modify itself, while leaving the core blog and CMS functionality in tact. It can be used on new and existing sites.

After you deploy this, it will be up to you to keep your site up to date yourself manually.

## Apache 2.4 .htaccess files
- `/.htaccess`: 
  - Deny directory browsing
  - Block include-only files
  - Deny access to wp-config.php
  - Deny access to .htaccess files
  - Deny access to misc file types that shouldn't need to be accessed in a production environment
  - Optionally prevent hotlinking of images (configure & uncomment yourself)
  - Optionally restrict wp-login.php to specific IPs (configure & uncomment it yourself)

- `/wp-admin/.htaccess`:
  - Optionally restrict by IP address (configure and uncomment yourself)
  
- `/wp-content/.htaccess`:
  - Completely disable php execution
  - Only allow direct access to safe media files (css, js, images)

- `/wp-includes/.htaccess`:
  - Disable access to all but 2 php files

## Helper scripts
Run them from the base of your WP install.
- `harden-wordpress.sh`:
  - Puts all the .htaccess files in place
  - Backs up anything it overwrites to your home dir 
  - Adds the `DISALLOW_FILE_EDIT` directive to wp-config.php
  - Is verbose about what it does
- `fix-wordpress-perissions.sh`:
  - Helps you reset all the permissions so Wordpress can only write to the `/wp-content/uploads` directory

## Don't be tempted

The above config results in PHP only having write access to the `/wp-content/uploads` folder, but not having any ability to execute there. This is the only safe way to operate your site - wherever PHP can write to, it must *NOT* be able to execute scripts.

You can expect plugins to complain about the lack of write access to the `/wp-content` folder. Consider very carefully which additional folders (if any) you give write access to. Chances are none of them actually need it. Giving PHP write access to anything above `/wp-content/uploads` will eventually compromise your server unless you also disable PHP execution for that folder at the same time.

## Versions tested
- Wordpress 4.6 + Apache 2.4 + Ubuntu 14.04
- Wordpress 4.1 + Apache 2.4 + Ubuntu 12.04
